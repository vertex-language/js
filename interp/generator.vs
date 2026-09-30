package interp

import (
    "js/object"
    "js/str"
    "js/value"
)

/// Resumption is what an await resumes when its value settles.
enum Resumption {
    case asyncFunction(Frame, object.PromiseObject)
    case asyncGenerator(GeneratorObject, Frame)
}

enum GeneratorState: Equatable {
    case suspendedStart
    case suspendedYield
    case executing
    case awaitingReturn
    case completed
}

/// AsyncGeneratorRequest is a queued next, throw or return (§27.6.3.1).
final class AsyncGeneratorRequest {
    let mode: int       // 0 next, 1 throw, 2 return
    let value: Value
    let promise: object.PromiseObject
    init(mode: int, value: Value, promise: object.PromiseObject) {
        self.mode = mode
        self.value = value
        self.promise = promise
    }
}

/// GeneratorObject is a generator or async generator instance: its
/// suspended frame and state.
final class GeneratorObject: object.JSObject {
    var frame: Frame?
    var state: GeneratorState = .suspendedStart
    let isAsync: bool
    var queue: [AsyncGeneratorRequest] = []

    init(frame: Frame, isAsync: bool, proto: object.JSObject?) {
        self.frame = frame
        self.isAsync = isAsync
        super.init(proto: proto)
        self.Kind = isAsync ? .asyncGenerator : .generator
    }
}

/// ForInIterator enumerates an object's string keys and its prototypes'
/// for for-in (§14.7.5.9): each key once, enumerable ones only, skipping
/// keys deleted before their turn.
final class ForInIterator: object.JSObject {
    var current: object.JSObject?
    var holder: object.JSObject?
    var pending: [value.PropertyKey] = []
    var next: int = 0
    var visited: [value.PropertyKey: bool] = [:]

    init(_ o: object.JSObject) {
        self.current = o
        super.init(proto: nil)
    }

    func Next() throws -> Value? {
        while true {
            if next >= pending.count {
                guard let c = current else { return nil }
                holder = c
                pending = try c.OwnPropertyKeys()
                next = 0
                current = try c.GetPrototypeOf()
                continue
            }
            let k = pending[next]
            next += 1
            if k.IsSymbol { continue }
            if visited[k] != nil { continue }
            visited[k] = true
            guard let d = try holder!.GetOwnProperty(k) else { continue }
            if d.Enumerable != true { continue }
            return object.KeyToValue(k)
        }
    }
}

extension Engine {
    // MARK: generators

    func startGenerator(_ f: Frame, async: bool) throws -> Value {
        _ = try run(f)
        let r = f.realm
        var proto = async ? r.AsyncGeneratorPrototype : r.GeneratorPrototype
        if let fn = f.fn, case .object(let p) = try fn.Get(value.PropertyKey.Named("prototype"), .object(fn)) {
            proto = p
        }
        let g = GeneratorObject(frame: f, isAsync: async, proto: proto)
        return .object(g)
    }

    func generatorResume(_ g: GeneratorObject, _ mode: int, _ v: Value) throws -> Value {
        switch g.state {
        case .executing:
            throw object.ThrowTypeError("Generator is already running")
        case .completed:
            if mode == 1 { throw object.Completion(v) }
            return .object(object.CreateIterResultObject(mode == 2 ? v : .undefined, true))
        case .suspendedStart:
            if mode != 0 {
                g.state = .completed
                g.frame = nil
                if mode == 1 { throw object.Completion(v) }
                return .object(object.CreateIterResultObject(v, true))
            }
        default:
            break
        }
        guard let f = g.frame else {
            return .object(object.CreateIterResultObject(.undefined, true))
        }
        if g.state == .suspendedYield {
            f.regs[int(f.yieldModeReg)] = .number(float64(mode))
            f.regs[int(f.yieldValueReg)] = v
        }
        g.state = .executing
        let e: Exit
        do {
            e = try run(f)
        } catch {
            g.state = .completed
            g.frame = nil
            throw error
        }
        switch e {
        case .yielded(let yv, let raw):
            g.state = .suspendedYield
            return raw ? yv : .object(object.CreateIterResultObject(yv, false))
        case .returned(let rv):
            g.state = .completed
            g.frame = nil
            return .object(object.CreateIterResultObject(rv, true))
        default:
            g.state = .completed
            g.frame = nil
            return .object(object.CreateIterResultObject(.undefined, true))
        }
    }

    // MARK: async functions

    func startAsync(_ f: Frame) throws -> Value {
        let p = object.PromiseObject(proto: f.realm.PromisePrototype)
        asyncStep(f, p, throwing: nil)
        return .object(p)
    }

    /// asyncStep runs an async function's frame until it returns, throws or awaits.
    func asyncStep(_ f: Frame, _ p: object.PromiseObject, throwing: Value?) {
        do {
            let e = try run(f, throwing: throwing)
            switch e {
            case .returned(let v):
                object.ResolvePromise(p, v)
            case .awaited(let v):
                awaitValue(f, v, .asyncFunction(f, p))
            default:
                break
            }
        } catch let c as object.Completion {
            object.RejectPromise(p, c.Value)
        } catch {
        }
    }

    /// awaitValue is Await (§6.2.3.1): when v settles, the frame resumes with
    /// its value in the accumulator, or by throwing its reason.
    func awaitValue(_ f: Frame, _ v: Value, _ k: Resumption) {
        do {
            try object.AwaitValue(v, onFulfilled: { [unowned self] val in
                f.acc = val
                self.resume(k, nil)
                return .undefined
            }, onRejected: { [unowned self] err in
                // Throw at the await itself.
                f.pc -= 1
                self.resume(k, err)
                return .undefined
            })
        } catch let c as object.Completion {
            // Resolving v threw (a poisoned constructor getter): throw it in.
            f.pc -= 1
            resume(k, c.Value)
        } catch {
        }
    }

    func resume(_ k: Resumption, _ thrown: Value?) {
        switch k {
        case .asyncFunction(let f, let p):
            asyncStep(f, p, throwing: thrown)
        case .asyncGenerator(let g, let f):
            asyncGeneratorRun(g, f, throwing: thrown)
        }
    }

    // MARK: async generators

    func asyncGeneratorEnqueue(_ thisV: Value, _ mode: int, _ v: Value) -> Value {
        let r = object.CurrentRealm()
        let p = object.PromiseObject(proto: r.PromisePrototype)
        guard case .object(let o) = thisV, let g = o as? GeneratorObject, g.isAsync else {
            object.RejectPromise(p, .object(object.MakeError(r.TypeErrorPrototype, str.JSString.From("next method called on incompatible receiver \(object.Describe(thisV))"))))
            return .object(p)
        }
        g.queue.append(AsyncGeneratorRequest(mode: mode, value: v, promise: p))
        if g.state != .executing && g.state != .awaitingReturn {
            asyncGeneratorResumeNext(g)
        }
        return .object(p)
    }

    func asyncGeneratorResumeNext(_ g: GeneratorObject) {
        while true {
            if g.state == .executing || g.state == .awaitingReturn { return }
            guard let req = g.queue.first else { return }
            if req.mode != 0 {
                if g.state == .suspendedStart {
                    g.state = .completed
                    g.frame = nil
                }
                if g.state == .completed {
                    if req.mode == 2 {
                        g.state = .awaitingReturn
                        do {
                            try object.AwaitValue(req.value, onFulfilled: { [unowned self] v in
                                g.state = .completed
                                self.asyncGeneratorSettle(g, v, done: true, rejected: false)
                                return .undefined
                            }, onRejected: { [unowned self] err in
                                g.state = .completed
                                self.asyncGeneratorSettle(g, err, done: true, rejected: true)
                                return .undefined
                            })
                        } catch let c as object.Completion {
                            g.state = .completed
                            asyncGeneratorSettle(g, c.Value, done: true, rejected: true)
                        } catch {
                        }
                        return
                    }
                    _ = g.queue.removeFirst()
                    object.RejectPromise(req.promise, req.value)
                    continue
                }
            } else if g.state == .completed {
                _ = g.queue.removeFirst()
                object.ResolvePromise(req.promise, .object(object.CreateIterResultObject(.undefined, true)))
                continue
            }
            guard let f = g.frame else { return }
            if g.state == .suspendedYield {
                f.regs[int(f.yieldModeReg)] = .number(float64(req.mode))
                f.regs[int(f.yieldValueReg)] = req.value
            }
            g.state = .executing
            asyncGeneratorRun(g, f, throwing: nil)
            return
        }
    }

    /// asyncGeneratorSettle settles the request at the head of the queue and
    /// moves on to the next one.
    func asyncGeneratorSettle(_ g: GeneratorObject, _ v: Value, done: bool, rejected: bool) {
        if g.queue.isEmpty { return }
        let req = g.queue.removeFirst()
        if rejected {
            object.RejectPromise(req.promise, v)
        } else {
            object.ResolvePromise(req.promise, .object(object.CreateIterResultObject(v, done)))
        }
        asyncGeneratorResumeNext(g)
    }

    func asyncGeneratorRun(_ g: GeneratorObject, _ f: Frame, throwing: Value?) {
        let e: Exit
        do {
            e = try run(f, throwing: throwing)
        } catch let c as object.Completion {
            g.state = .completed
            g.frame = nil
            asyncGeneratorSettle(g, c.Value, done: true, rejected: true)
            return
        } catch {
            return
        }
        switch e {
        case .yielded(let v, _):
            g.state = .suspendedYield
            asyncGeneratorSettle(g, v, done: false, rejected: false)
        case .returned(let v):
            g.state = .completed
            g.frame = nil
            asyncGeneratorSettle(g, v, done: true, rejected: false)
        case .awaited(let v):
            awaitValue(f, v, .asyncGenerator(g, f))
        case .started, .call:
            break
        }
    }

    // MARK: the prototypes' methods

    /// Install gives a realm the methods that run generators, async
    /// generators and async-from-sync iterators, which live here beside
    /// the frames they resume.
    public func Install(_ r: object.Realm) {
        r.Engine = self
        let gp = r.GeneratorPrototype
        r.Method(gp, "next", 1) { [unowned self] thisV, args, _ in
            let g = try self.generatorOf(thisV, "next")
            return try self.generatorResume(g, 0, args.isEmpty ? .undefined : args[0])
        }
        r.Method(gp, "return", 1) { [unowned self] thisV, args, _ in
            let g = try self.generatorOf(thisV, "return")
            return try self.generatorResume(g, 2, args.isEmpty ? .undefined : args[0])
        }
        r.Method(gp, "throw", 1) { [unowned self] thisV, args, _ in
            let g = try self.generatorOf(thisV, "throw")
            return try self.generatorResume(g, 1, args.isEmpty ? .undefined : args[0])
        }
        gp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("Generator")), writable: false, enumerable: false, configurable: true)
        let agp = r.AsyncGeneratorPrototype
        r.Method(agp, "next", 1) { [unowned self] thisV, args, _ in
            return self.asyncGeneratorEnqueue(thisV, 0, args.isEmpty ? .undefined : args[0])
        }
        r.Method(agp, "return", 1) { [unowned self] thisV, args, _ in
            return self.asyncGeneratorEnqueue(thisV, 2, args.isEmpty ? .undefined : args[0])
        }
        r.Method(agp, "throw", 1) { [unowned self] thisV, args, _ in
            return self.asyncGeneratorEnqueue(thisV, 1, args.isEmpty ? .undefined : args[0])
        }
        agp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("AsyncGenerator")), writable: false, enumerable: false, configurable: true)
        installAsyncFromSync(r)
    }

    func generatorOf(_ v: Value, _ method: string) throws -> GeneratorObject {
        guard case .object(let o) = v, let g = o as? GeneratorObject, !g.isAsync else {
            throw object.ThrowTypeError("\(method) method called on incompatible receiver \(object.Describe(v))")
        }
        return g
    }

    /// installAsyncFromSync defines %AsyncFromSyncIteratorPrototype%'s
    /// methods (§27.1.6.2): the sync iterator's results, with their values
    /// awaited.
    func installAsyncFromSync(_ r: object.Realm) {
        let p = r.AsyncFromSyncIteratorPrototype
        for (name, mode) in [("next", 0), ("return", 2), ("throw", 1)] {
            r.Method(p, name, 1) { thisV, args, _ in
                let promise = object.PromiseObject(proto: r.PromisePrototype)
                guard case .object(let o) = thisV, let it = o as? object.AsyncFromSyncIterator else {
                    object.RejectPromise(promise, .object(object.MakeError(r.TypeErrorPrototype, str.JSString.From("not an async-from-sync iterator"))))
                    return .object(promise)
                }
                let sync = it.Sync
                do {
                    var result: Value
                    if mode == 0 {
                        result = args.isEmpty ? try object.Call(sync.NextMethod, .object(sync.Iterator), []) : try object.Call(sync.NextMethod, .object(sync.Iterator), [args[0]])
                    } else {
                        let m = try object.GetMethod(.object(sync.Iterator), value.PropertyKey.Named(name))
                        if m.IsUndefined {
                            if mode == 2 {
                                object.ResolvePromise(promise, .object(object.CreateIterResultObject(args.isEmpty ? .undefined : args[0], true)))
                                return .object(promise)
                            }
                            // No throw: close the iterator, then reject.
                            object.IteratorCloseOnThrow(sync)
                            object.RejectPromise(promise, .object(object.MakeError(r.TypeErrorPrototype, str.JSString.From("The iterator does not provide a 'throw' method"))))
                            return .object(promise)
                        }
                        result = args.isEmpty ? try object.Call(m, .object(sync.Iterator), []) : try object.Call(m, .object(sync.Iterator), [args[0]])
                    }
                    guard case .object(let ro) = result else {
                        throw object.ThrowTypeError("Iterator result \(object.Describe(result)) is not an object")
                    }
                    let done = try object.IteratorComplete(ro)
                    let v = try object.IteratorValue(ro)
                    let vp = try object.PromiseResolve(r.PromiseConstructor!, v)
                    guard let vpo = vp as? object.PromiseObject else { return .object(promise) }
                    object.PerformPromiseThen(vpo, .native({ val in
                        object.ResolvePromise(promise, .object(object.CreateIterResultObject(val, done)))
                        return .undefined
                    }), .native({ err in
                        if !done && mode != 2 { object.IteratorCloseOnThrow(sync) }
                        object.RejectPromise(promise, err)
                        return .undefined
                    }), nil)
                } catch let c as object.Completion {
                    object.RejectPromise(promise, c.Value)
                }
                return .object(promise)
            }
        }
    }
}

// MARK: explicit resource management (ES2026)

/// DisposeScope is a scope's DisposeCapability: the resources its using
/// declarations added, and the error disposing them has produced.
final class DisposeScope: object.JSObject {
    struct Resource {
        var value: Value
        var method: Value      // undefined for await using of null or undefined
        var async: bool
        var awaitResult: bool  // false when the method is a sync @@dispose used by await using
    }

    var resources: [Resource] = []
    var Error: Value? = nil
    /// needsAwait and hasAwaited are DisposeResources' bookkeeping: an
    /// await using of null or undefined owes one await, paid at the end
    /// unless some disposal awaited anyway.
    var needsAwait: bool = false
    var hasAwaited: bool = false

    /// Add is AddDisposableResource with CreateDisposableResource (§9.4.3).
    func Add(_ v: Value, async: bool) throws {
        if v.IsNullish {
            if async { resources.append(Resource(value: .undefined, method: .undefined, async: true, awaitResult: false)) }
            return
        }
        guard v.IsObject else {
            throw object.ThrowTypeError("\(object.Describe(v)) is not disposable")
        }
        if async {
            let m = try object.GetMethod(v, .symbol(value.SymAsyncDispose))
            if !m.IsUndefined {
                resources.append(Resource(value: v, method: m, async: true, awaitResult: true))
                return
            }
            let s = try object.GetMethod(v, .symbol(value.SymDispose))
            if s.IsUndefined { throw object.ThrowTypeError("\(object.Describe(v)) is not async disposable") }
            resources.append(Resource(value: v, method: s, async: true, awaitResult: false))
            return
        }
        let m = try object.GetMethod(v, .symbol(value.SymDispose))
        if m.IsUndefined { throw object.ThrowTypeError("\(object.Describe(v)) is not disposable") }
        resources.append(Resource(value: v, method: m, async: false, awaitResult: false))
    }

    /// Next is one step of DisposeResources (ES2026 §9.4.5): (0, _) when
    /// nothing is left, (1, _) when a resource was disposed, (2, v) when v
    /// is to be awaited first.
    func Next(_ r: object.Realm) -> (int, Value) {
        while true {
            guard let res = resources.popLast() else {
                if needsAwait && !hasAwaited {
                    needsAwait = false
                    hasAwaited = true
                    return (2, .undefined)
                }
                return (0, .undefined)
            }
            if !res.async && needsAwait && !hasAwaited {
                // A sync resource after an owed await: pay it first.
                resources.append(res)
                needsAwait = false
                return (2, .undefined)
            }
            if res.method.IsUndefined {
                needsAwait = true
                continue
            }
            do {
                let result = try object.Call(res.method, res.value, [])
                if res.async {
                    hasAwaited = true
                    return (2, res.awaitResult ? result : .undefined)
                }
            } catch let c as object.Completion {
                Record(c.Value, r)
            } catch {
            }
            return (1, .undefined)
        }
    }

    /// Record adds an error: the first is kept as is, each later one wraps
    /// what came before as a SuppressedError.
    func Record(_ e: Value, _ r: object.Realm) {
        guard let prev = Error else {
            Error = e
            return
        }
        let proto = r.Intrinsics["SuppressedErrorPrototype"] ?? r.ErrorPrototype
        let se = object.MakeError(proto, str.JSString.From("An error was suppressed during disposal."))
        se.DefineData(object.Key("error"), e, writable: true, enumerable: false, configurable: true)
        se.DefineData(object.Key("suppressed"), prev, writable: true, enumerable: false, configurable: true)
        Error = .object(se)
    }
}
