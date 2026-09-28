package object

import (
    "js/str"
    "js/value"
)

public enum PromiseState: Equatable {
    case pending
    case fulfilled
    case rejected
}

/// ReactionHandler is a reaction's handler: a function object, a Vertex
/// closure (for await and the engine's own jobs), or nothing (pass the
/// value through).
public enum ReactionHandler {
    case none
    case function(JSObject)
    case native((Value) throws -> Value)
}

/// PromiseCapability is the spec's PromiseCapability Record (§27.2.1.1).
public final class PromiseCapability {
    public let Promise: JSObject
    public let Resolve: Value
    public let Reject: Value
    public init(promise: JSObject, resolve: Value, reject: Value) {
        self.Promise = promise
        self.Resolve = resolve
        self.Reject = reject
    }
}

/// PromiseReaction is the spec's PromiseReaction Record (§27.2.1.2).
public final class PromiseReaction {
    public let Capability: PromiseCapability?
    public let IsFulfill: bool
    public let Handler: ReactionHandler
    public init(capability: PromiseCapability?, isFulfill: bool, handler: ReactionHandler) {
        self.Capability = capability
        self.IsFulfill = isFulfill
        self.Handler = handler
    }
}

/// PromiseObject is a promise instance (§27.2.6).
public final class PromiseObject: JSObject {
    public var State: PromiseState = .pending
    public var Result: Value = .undefined
    public var FulfillReactions: [PromiseReaction] = []
    public var RejectReactions: [PromiseReaction] = []
    public var IsHandled: bool = false

    public override init(proto: JSObject?) {
        super.init(proto: proto)
        self.Kind = .promise
    }
}

/// CreateResolvingFunctions (§27.2.1.3).
public func CreateResolvingFunctions(_ p: PromiseObject) -> (Value, Value) {
    let r = CurrentRealm()
    var alreadyResolved = false
    let resolve = NativeFunction(realm: r, name: "", length: 1) { _, args, _ in
        if alreadyResolved { return .undefined }
        alreadyResolved = true
        ResolvePromise(p, args.isEmpty ? .undefined : args[0])
        return .undefined
    }
    let reject = NativeFunction(realm: r, name: "", length: 1) { _, args, _ in
        if alreadyResolved { return .undefined }
        alreadyResolved = true
        RejectPromise(p, args.isEmpty ? .undefined : args[0])
        return .undefined
    }
    return (.object(resolve), .object(reject))
}

/// ResolvePromise is the body of a promise resolve function.
public func ResolvePromise(_ p: PromiseObject, _ resolution: Value) {
    if case .object(let o) = resolution {
        if o === p {
            RejectPromise(p, .object(MakeError(CurrentRealm().TypeErrorPrototype, str.JSString.From("Chaining cycle detected for promise #<Promise>"))))
            return
        }
        var then: Value
        do {
            then = try o.Get(keyThen, resolution)
        } catch let c as Completion {
            RejectPromise(p, c.Value)
            return
        } catch {
            return
        }
        guard case .object(let thenFn) = then, thenFn.IsCallable else {
            FulfillPromise(p, resolution)
            return
        }
        // NewPromiseResolveThenableJob (§27.2.2.2).
        let realm = CurrentRealm()
        realm.Agent.Enqueue {
            let (res, rej) = CreateResolvingFunctions(p)
            do {
                _ = try thenFn.Call(resolution, [res, rej])
            } catch let c as Completion {
                _ = try Call(rej, .undefined, [c.Value])
            }
        }
        return
    }
    FulfillPromise(p, resolution)
}

/// FulfillPromise (§27.2.1.4).
public func FulfillPromise(_ p: PromiseObject, _ v: Value) {
    if p.State != .pending { return }
    let reactions = p.FulfillReactions
    p.Result = v
    p.FulfillReactions = []
    p.RejectReactions = []
    p.State = .fulfilled
    TriggerPromiseReactions(reactions, v)
}

/// RejectPromise (§27.2.1.7).
public func RejectPromise(_ p: PromiseObject, _ reason: Value) {
    if p.State != .pending { return }
    let reactions = p.RejectReactions
    p.Result = reason
    p.FulfillReactions = []
    p.RejectReactions = []
    p.State = .rejected
    if !p.IsHandled {
        if let t = CurrentRealm().Agent.OnRejectionTracker { t(p, false) }
    }
    TriggerPromiseReactions(reactions, reason)
}

func TriggerPromiseReactions(_ reactions: [PromiseReaction], _ arg: Value) {
    let agent = CurrentRealm().Agent
    for reaction in reactions {
        agent.Enqueue { try PromiseReactionJob(reaction, arg) }
    }
}

/// PromiseReactionJob is NewPromiseReactionJob's job (§27.2.2.1).
func PromiseReactionJob(_ reaction: PromiseReaction, _ arg: Value) throws {
    var result: Value = .undefined
    var threw = false
    switch reaction.Handler {
    case .none:
        result = arg
        threw = !reaction.IsFulfill
    case .function(let f):
        do {
            result = try f.Call(.undefined, [arg])
        } catch let c as Completion {
            result = c.Value
            threw = true
        }
    case .native(let fn):
        do {
            result = try fn(arg)
        } catch let c as Completion {
            result = c.Value
            threw = true
        }
    }
    guard let cap = reaction.Capability else {
        if threw {
            // An engine-internal reaction threw: report it.
            throw Completion.thrown(result)
        }
        return
    }
    if threw {
        _ = try Call(cap.Reject, .undefined, [result])
    } else {
        _ = try Call(cap.Resolve, .undefined, [result])
    }
}

/// NewPromiseCapability (§27.2.1.5).
public func NewPromiseCapability(_ c: Value) throws -> PromiseCapability {
    guard case .object(let ctor) = c, ctor.IsConstructor else {
        throw ThrowTypeError("Promise resolve or reject function is not callable")
    }
    let r = CurrentRealm()
    if let pc = r.PromiseConstructor, ctor === pc {
        let p = PromiseObject(proto: r.PromisePrototype)
        let (res, rej) = CreateResolvingFunctions(p)
        return PromiseCapability(promise: p, resolve: res, reject: rej)
    }
    var resolve: Value = .undefined
    var reject: Value = .undefined
    let executor = NativeFunction(realm: r, name: "", length: 2) { _, args, _ in
        if !resolve.IsUndefined { throw ThrowTypeError("Promise executor has already been invoked with non-undefined arguments") }
        if !reject.IsUndefined { throw ThrowTypeError("Promise executor has already been invoked with non-undefined arguments") }
        resolve = args.count > 0 ? args[0] : .undefined
        reject = args.count > 1 ? args[1] : .undefined
        return .undefined
    }
    let pv = try ctor.Construct([.object(executor)], ctor)
    if !resolve.IsCallable || !reject.IsCallable {
        throw ThrowTypeError("Promise resolve or reject function is not callable")
    }
    guard case .object(let po) = pv else { throw ThrowTypeError("Promise constructor returned a non-object") }
    return PromiseCapability(promise: po, resolve: resolve, reject: reject)
}

/// NewPromise makes a pending %Promise% of the current realm.
public func NewPromise() -> PromiseObject {
    return PromiseObject(proto: CurrentRealm().PromisePrototype)
}

/// PromiseResolve (§27.2.4.7.1).
public func PromiseResolve(_ c: JSObject, _ x: Value) throws -> JSObject {
    if case .object(let xo) = x, xo is PromiseObject {
        let ctor = try xo.Get(keyConstructor, x)
        if case .object(let co) = ctor, co === c { return xo }
    }
    let cap = try NewPromiseCapability(.object(c))
    _ = try Call(cap.Resolve, .undefined, [x])
    return cap.Promise
}

/// PerformPromiseThen (§27.2.5.4.1).
public func PerformPromiseThen(_ p: PromiseObject, _ onFulfilled: ReactionHandler, _ onRejected: ReactionHandler, _ cap: PromiseCapability?) {
    let fr = PromiseReaction(capability: cap, isFulfill: true, handler: onFulfilled)
    let rr = PromiseReaction(capability: cap, isFulfill: false, handler: onRejected)
    let agent = CurrentRealm().Agent
    switch p.State {
    case .pending:
        p.FulfillReactions.append(fr)
        p.RejectReactions.append(rr)
    case .fulfilled:
        let v = p.Result
        agent.Enqueue { try PromiseReactionJob(fr, v) }
    case .rejected:
        let v = p.Result
        if !p.IsHandled {
            if let t = agent.OnRejectionTracker { t(p, true) }
        }
        agent.Enqueue { try PromiseReactionJob(rr, v) }
    }
    p.IsHandled = true
}

/// HandlerFrom turns a then argument into a reaction handler.
public func HandlerFrom(_ v: Value) -> ReactionHandler {
    if case .object(let o) = v, o.IsCallable { return .function(o) }
    return .none
}

/// AwaitValue is the core of Await (§6.2.3.1): resolve v to a promise and
/// react to it with Vertex closures.
public func AwaitValue(_ v: Value, onFulfilled: @escaping (Value) throws -> Value, onRejected: @escaping (Value) throws -> Value) throws {
    let r = CurrentRealm()
    let p = try PromiseResolve(r.PromiseConstructor!, v)
    guard let po = p as? PromiseObject else {
        throw ThrowTypeError("await: not a promise")
    }
    PerformPromiseThen(po, .native(onFulfilled), .native(onRejected), nil)
}

let unusedPromiseSymbol = value.SymSpecies
