// Package control installs the control abstraction objects (ECMA-262
// §27): Iterator and its helpers, %AsyncIteratorPrototype%, Promise,
// and the GeneratorFunction, AsyncGeneratorFunction and AsyncFunction
// constructors. The generator prototypes' next/return/throw are the
// interpreter's, beside the frames they resume.
package control

import (
    "js/object"
    "js/str"
    "js/value"
)

typealias Value = object.Value

func key(_ s: string) -> value.PropertyKey { return value.PropertyKey.Named(s) }

/// Install defines the control abstraction objects.
public func Install(_ r: object.Realm) {
    installIterator(r)
    installPromise(r)
    installFunctionKinds(r)
    installDispose(r)
}

/// thrown is the value a Completion carries, for rejecting with.
func thrown(_ e: Error) -> Value? {
    if let c = e as? object.Completion { return c.Value }
    return nil
}

// MARK: Iterator (§27.1)

/// IteratorHelper is an Iterator Helper object (§27.1.2.1): its steps
/// are a Vertex closure over the underlying iterator.
public final class IteratorHelper: object.JSObject {
    public let Underlying: object.IteratorRecord
    /// Step makes the next value, or nil when done.
    let step: () throws -> Value?
    public var Running: bool = false
    public var Done: bool = false
    public var Started: bool = false

    public init(_ underlying: object.IteratorRecord, proto: object.JSObject, _ step: @escaping () throws -> Value?) {
        self.Underlying = underlying
        self.step = step
        super.init(proto: proto)
    }

    public func Next() throws -> Value? {
        return try step()
    }
}

/// WrappedIterator is Iterator.from's wrapper (§27.1.3.2.1.1).
public final class WrappedIterator: object.JSObject {
    public let Iterated: object.IteratorRecord
    public init(_ it: object.IteratorRecord, proto: object.JSObject) {
        self.Iterated = it
        super.init(proto: proto)
    }
}

/// directIterator is GetIteratorDirect (§7.4.13).
func directIterator(_ v: Value) throws -> object.IteratorRecord {
    guard case .object(let o) = v else {
        throw object.ThrowTypeError("\(object.Describe(v)) is not an object")
    }
    return object.IteratorRecord(iterator: o, next: try o.Get(key("next"), v))
}

func callable(_ v: Value, _ what: string) throws -> Value {
    if !v.IsCallable { throw object.ThrowTypeError("\(object.Describe(v)) is not a function") }
    return v
}

func installIterator(_ r: object.Realm) {
    let ip = r.IteratorPrototype
    r.SymbolMethod(ip, value.SymIterator, 0) { thisV, _, _ in return thisV }
    r.SymbolMethod(r.AsyncIteratorPrototype, value.SymAsyncIterator, 0) { thisV, _, _ in return thisV }

    // The abstract Iterator constructor (§27.1.3.1).
    let ctor = r.Constructor("Iterator", 0, prototype: ip) { _, _, nt in
        guard let n = nt, n !== r.Intrinsics["Iterator"]! else {
            throw object.ThrowTypeError("Abstract class Iterator not directly constructable")
        }
        return .object(try object.OrdinaryCreateFromConstructor(n, r.IteratorPrototype))
    }
    r.Intrinsics["Iterator"] = ctor

    // Iterator.prototype[@@toStringTag] and .constructor are accessors
    // (§27.1.4.14, §27.1.4.1) with SetterThatIgnoresPrototypeProperties.
    func ignoringSetter(_ k: value.PropertyKey) -> object.NativeFn {
        return { thisV, args, _ in
            guard case .object(let o) = thisV else { throw object.ThrowTypeError("Iterator setter called on non-object") }
            if o === r.IteratorPrototype { throw object.ThrowTypeError("Cannot assign to read only property of Iterator.prototype") }
            if try o.GetOwnProperty(k) == nil {
                try object.CreateDataPropertyOrThrow(o, k, object.Arg(args, 0))
            } else {
                try object.SetProperty(o, k, object.Arg(args, 0), throwing: true)
            }
            return .undefined
        }
    }
    let tagKey = value.PropertyKey.symbol(value.SymToStringTag)
    ip.DefineAccessorDirect(tagKey,
        getter: r.Function("get [Symbol.toStringTag]", 0) { _, _, _ in return .string(str.Name("Iterator")) },
        setter: r.Function("set [Symbol.toStringTag]", 1, ignoringSetter(tagKey)),
        enumerable: false, configurable: true)
    ip.DefineAccessorDirect(key("constructor"),
        getter: r.Function("get constructor", 0) { _, _, _ in return .object(ctor) },
        setter: r.Function("set constructor", 1, ignoringSetter(key("constructor"))),
        enumerable: false, configurable: true)

    // %IteratorHelperPrototype% (§27.1.2.1).
    let hp = object.JSObject(proto: ip)
    r.Intrinsics["IteratorHelperPrototype"] = hp
    r.Method(hp, "next", 0) { thisV, _, _ in
        guard case .object(let o) = thisV, let h = o as? IteratorHelper else {
            throw object.ThrowTypeError("Method Iterator Helper.prototype.next called on incompatible receiver \(object.Describe(thisV))")
        }
        if h.Running { throw object.ThrowTypeError("Generator is already running") }
        if h.Done { return .object(object.CreateIterResultObject(.undefined, true)) }
        h.Running = true
        h.Started = true
        defer { h.Running = false }
        do {
            if let v = try h.Next() {
                return .object(object.CreateIterResultObject(v, false))
            }
        } catch {
            h.Done = true
            throw error
        }
        h.Done = true
        return .object(object.CreateIterResultObject(.undefined, true))
    }
    r.Method(hp, "return", 0) { thisV, _, _ in
        guard case .object(let o) = thisV, let h = o as? IteratorHelper else {
            throw object.ThrowTypeError("Method Iterator Helper.prototype.return called on incompatible receiver \(object.Describe(thisV))")
        }
        if h.Running { throw object.ThrowTypeError("Generator is already running") }
        if !h.Done {
            h.Done = true
            try object.IteratorClose(h.Underlying)
        }
        return .object(object.CreateIterResultObject(.undefined, true))
    }
    hp.DefineData(tagKey, .string(str.Name("Iterator Helper")), writable: false, enumerable: false, configurable: true)

    // %WrapForValidIteratorPrototype% (§27.1.3.2.1.1).
    let wp = object.JSObject(proto: ip)
    r.Method(wp, "next", 0) { thisV, _, _ in
        guard case .object(let o) = thisV, let w = o as? WrappedIterator else {
            throw object.ThrowTypeError("next called on incompatible receiver")
        }
        return try object.Call(w.Iterated.NextMethod, .object(w.Iterated.Iterator), [])
    }
    r.Method(wp, "return", 0) { thisV, _, _ in
        guard case .object(let o) = thisV, let w = o as? WrappedIterator else {
            throw object.ThrowTypeError("return called on incompatible receiver")
        }
        let ret = try object.GetMethod(.object(w.Iterated.Iterator), key("return"))
        if ret.IsUndefined { return .object(object.CreateIterResultObject(.undefined, true)) }
        return try object.Call(ret, .object(w.Iterated.Iterator), [])
    }

    r.Method(ctor, "from", 1) { _, args, _ in
        let o = object.Arg(args, 0)
        var rec: object.IteratorRecord
        if case .string = o {
            rec = try object.GetIterator(o)
        } else {
            guard case .object = o else { throw object.ThrowTypeError("\(object.Describe(o)) is not an object") }
            let m = try object.GetMethod(o, .symbol(value.SymIterator))
            rec = m.IsUndefined ? try directIterator(o) : try object.GetIteratorFromMethod(o, m)
        }
        if try object.OrdinaryHasInstance(.object(ctor), .object(rec.Iterator)) {
            return .object(rec.Iterator)
        }
        return .object(WrappedIterator(rec, proto: wp))
    }
    r.Method(ctor, "concat", 0) { _, args, _ in
        var iterables: [(Value, Value)] = []
        for a in args {
            guard case .object = a else { throw object.ThrowTypeError("\(object.Describe(a)) is not an object") }
            let m = try object.GetMethod(a, .symbol(value.SymIterator))
            if m.IsUndefined { throw object.ThrowTypeError("\(object.DescribeIterable(a)) is not iterable") }
            iterables.append((a, m))
        }
        var i = 0
        var current: object.IteratorRecord? = nil
        let dummy = object.IteratorRecord(iterator: object.JSObject(proto: nil), next: .undefined)
        var helper: IteratorHelper? = nil
        helper = IteratorHelper(dummy, proto: hp) {
            while true {
                if let cur = current {
                    if let v = try object.IteratorStepValue(cur) { return v }
                    current = nil
                    continue
                }
                if i >= iterables.count { return nil }
                let (it, m) = iterables[i]
                i += 1
                current = try object.GetIteratorFromMethod(it, m)
            }
        }
        _ = helper
        return .object(helper!)
    }

    // The helpers (§27.1.4).
    func helperThis(_ thisV: Value) throws -> object.JSObject {
        guard case .object(let o) = thisV else {
            throw object.ThrowTypeError("Iterator helper called on non-object \(object.Describe(thisV))")
        }
        return o
    }
    func closeAndThrow(_ o: object.JSObject, _ e: Error) -> Error {
        let rec = object.IteratorRecord(iterator: o, next: .undefined)
        object.IteratorCloseOnThrow(rec)
        return e
    }
    r.Method(ip, "map", 1) { thisV, args, _ in
        let o = try helperThis(thisV)
        let fn = object.Arg(args, 0)
        if !fn.IsCallable { throw closeAndThrow(o, object.ThrowTypeError("\(object.Describe(fn)) is not a function")) }
        let rec = try directIterator(thisV)
        var counter = 0
        return .object(IteratorHelper(rec, proto: hp) {
            guard let v = try object.IteratorStepValue(rec) else { return nil }
            do {
                let m = try object.Call(fn, .undefined, [v, .number(float64(counter))])
                counter += 1
                return m
            } catch {
                object.IteratorCloseOnThrow(rec)
                throw error
            }
        })
    }
    r.Method(ip, "filter", 1) { thisV, args, _ in
        let o = try helperThis(thisV)
        let fn = object.Arg(args, 0)
        if !fn.IsCallable { throw closeAndThrow(o, object.ThrowTypeError("\(object.Describe(fn)) is not a function")) }
        let rec = try directIterator(thisV)
        var counter = 0
        return .object(IteratorHelper(rec, proto: hp) {
            while true {
                guard let v = try object.IteratorStepValue(rec) else { return nil }
                do {
                    let keep = try object.Call(fn, .undefined, [v, .number(float64(counter))]).Truthy
                    counter += 1
                    if keep { return v }
                } catch {
                    object.IteratorCloseOnThrow(rec)
                    throw error
                }
            }
        })
    }
    func limit(_ o: object.JSObject, _ v: Value) throws -> float64 {
        var n: float64 = 0
        do {
            n = try object.ToNumber(v)
        } catch {
            throw closeAndThrow(o, error)
        }
        if n.isNaN { throw closeAndThrow(o, object.ThrowRangeError("\(object.Describe(v)) must be positive")) }
        let i = value.ToIntegerOrInfinity(n)
        if i < 0 { throw closeAndThrow(o, object.ThrowRangeError("\(object.Describe(v)) must be positive")) }
        return i
    }
    r.Method(ip, "take", 1) { thisV, args, _ in
        let o = try helperThis(thisV)
        var remaining = try limit(o, object.Arg(args, 0))
        let rec = try directIterator(thisV)
        return .object(IteratorHelper(rec, proto: hp) {
            if remaining == 0 {
                try object.IteratorClose(rec)
                return nil
            }
            if remaining != float64.infinity { remaining -= 1 }
            return try object.IteratorStepValue(rec)
        })
    }
    r.Method(ip, "drop", 1) { thisV, args, _ in
        let o = try helperThis(thisV)
        var remaining = try limit(o, object.Arg(args, 0))
        let rec = try directIterator(thisV)
        return .object(IteratorHelper(rec, proto: hp) {
            while remaining > 0 {
                if remaining != float64.infinity { remaining -= 1 }
                if try object.IteratorStepValue(rec) == nil { return nil }
            }
            return try object.IteratorStepValue(rec)
        })
    }
    r.Method(ip, "flatMap", 1) { thisV, args, _ in
        let o = try helperThis(thisV)
        let fn = object.Arg(args, 0)
        if !fn.IsCallable { throw closeAndThrow(o, object.ThrowTypeError("\(object.Describe(fn)) is not a function")) }
        let rec = try directIterator(thisV)
        var counter = 0
        var inner: object.IteratorRecord? = nil
        return .object(IteratorHelper(rec, proto: hp) {
            while true {
                if let inn = inner {
                    do {
                        if let v = try object.IteratorStepValue(inn) { return v }
                    } catch {
                        object.IteratorCloseOnThrow(rec)
                        throw error
                    }
                    inner = nil
                    continue
                }
                guard let v = try object.IteratorStepValue(rec) else { return nil }
                do {
                    let mapped = try object.Call(fn, .undefined, [v, .number(float64(counter))])
                    counter += 1
                    inner = try flattenable(mapped)
                } catch {
                    object.IteratorCloseOnThrow(rec)
                    throw error
                }
            }
        })
    }
    r.Method(ip, "reduce", 1) { thisV, args, _ in
        let o = try helperThis(thisV)
        let fn = object.Arg(args, 0)
        if !fn.IsCallable { throw closeAndThrow(o, object.ThrowTypeError("\(object.Describe(fn)) is not a function")) }
        let rec = try directIterator(thisV)
        var acc: Value = .undefined
        var counter = 0
        if args.count >= 2 {
            acc = args[1]
        } else {
            guard let first = try object.IteratorStepValue(rec) else {
                throw object.ThrowTypeError("Reduce of empty iterator with no initial value")
            }
            acc = first
            counter = 1
        }
        while let v = try object.IteratorStepValue(rec) {
            do {
                acc = try object.Call(fn, .undefined, [acc, v, .number(float64(counter))])
            } catch {
                object.IteratorCloseOnThrow(rec)
                throw error
            }
            counter += 1
        }
        return acc
    }
    r.Method(ip, "toArray", 0) { thisV, _, _ in
        _ = try helperThis(thisV)
        let rec = try directIterator(thisV)
        var out: [Value] = []
        while let v = try object.IteratorStepValue(rec) { out.append(v) }
        return .object(object.CreateArrayFromList(r, out))
    }
    r.Method(ip, "forEach", 1) { thisV, args, _ in
        let o = try helperThis(thisV)
        let fn = object.Arg(args, 0)
        if !fn.IsCallable { throw closeAndThrow(o, object.ThrowTypeError("\(object.Describe(fn)) is not a function")) }
        let rec = try directIterator(thisV)
        var counter = 0
        while let v = try object.IteratorStepValue(rec) {
            do {
                _ = try object.Call(fn, .undefined, [v, .number(float64(counter))])
            } catch {
                object.IteratorCloseOnThrow(rec)
                throw error
            }
            counter += 1
        }
        return .undefined
    }
    // some, every and find share a shape: stop on a verdict.
    func searching(_ name: string, _ onHit: @escaping (Value) -> Value, _ want: bool, _ none: Value) {
        r.Method(ip, name, 1) { thisV, args, _ in
            let o = try helperThis(thisV)
            let fn = object.Arg(args, 0)
            if !fn.IsCallable { throw closeAndThrow(o, object.ThrowTypeError("\(object.Describe(fn)) is not a function")) }
            let rec = try directIterator(thisV)
            var counter = 0
            while let v = try object.IteratorStepValue(rec) {
                var verdict = false
                do {
                    verdict = try object.Call(fn, .undefined, [v, .number(float64(counter))]).Truthy
                } catch {
                    object.IteratorCloseOnThrow(rec)
                    throw error
                }
                if verdict == want {
                    try object.IteratorClose(rec)
                    return onHit(v)
                }
                counter += 1
            }
            return none
        }
    }
    searching("some", { _ in return .bool(true) }, true, .bool(false))
    searching("every", { _ in return .bool(false) }, false, .bool(true))
    searching("find", { v in return v }, true, .undefined)
}

/// flattenable is GetIteratorFlattenable(v, reject-strings) (§7.4.12).
func flattenable(_ v: Value) throws -> object.IteratorRecord {
    guard case .object = v else { throw object.ThrowTypeError("\(object.Describe(v)) is not an object") }
    let m = try object.GetMethod(v, .symbol(value.SymIterator))
    if m.IsUndefined { return try directIterator(v) }
    let it = try object.Call(m, v, [])
    guard case .object = it else { throw object.ThrowTypeError("\(object.Describe(it)) is not an object") }
    return try directIterator(it)
}

// MARK: Promise (§27.2)

final class Counter {
    var n: int = 1
    var values: [Value] = []
}

func installPromise(_ r: object.Realm) {
    let pp = r.PromisePrototype
    let ctor = r.Constructor("Promise", 1, prototype: pp) { _, args, nt in
        guard let n = nt else {
            throw object.ThrowTypeError("Promise constructor cannot be invoked without 'new'")
        }
        let executor = object.Arg(args, 0)
        if !executor.IsCallable {
            throw object.ThrowTypeError("Promise resolver \(object.Describe(executor)) is not a function")
        }
        let proto = try object.GetPrototypeFromConstructor(n, r.PromisePrototype)
        let p = object.PromiseObject(proto: proto)
        let (res, rej) = object.CreateResolvingFunctions(p)
        do {
            _ = try object.Call(executor, .undefined, [res, rej])
        } catch {
            guard let v = thrown(error) else { throw error }
            _ = try object.Call(rej, .undefined, [v])
        }
        return .object(p)
    }
    r.PromiseConstructor = ctor
    r.Getter(ctor, .symbol(value.SymSpecies)) { thisV, _, _ in return thisV }
    pp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("Promise")), writable: false, enumerable: false, configurable: true)

    r.Method(pp, "then", 2) { thisV, args, _ in
        guard case .object(let o) = thisV, let p = o as? object.PromiseObject else {
            throw object.ThrowTypeError("Method Promise.prototype.then called on incompatible receiver \(object.Describe(thisV))")
        }
        let c = try object.SpeciesConstructor(p, ctor)
        let cap = try object.NewPromiseCapability(.object(c))
        object.PerformPromiseThen(p, object.HandlerFrom(object.Arg(args, 0)), object.HandlerFrom(object.Arg(args, 1)), cap)
        return .object(cap.Promise)
    }
    r.Method(pp, "catch", 1) { thisV, args, _ in
        return try object.Invoke(thisV, key("then"), [.undefined, object.Arg(args, 0)])
    }
    r.Method(pp, "finally", 1) { thisV, args, _ in
        guard case .object(let p) = thisV else {
            throw object.ThrowTypeError("Method Promise.prototype.finally called on incompatible receiver \(object.Describe(thisV))")
        }
        let c = try object.SpeciesConstructor(p, ctor)
        let onFinally = object.Arg(args, 0)
        if !onFinally.IsCallable {
            return try object.Invoke(thisV, key("then"), [onFinally, onFinally])
        }
        let thenFinally = r.Function("", 1) { _, a, _ in
            let v = object.Arg(a, 0)
            let result = try object.Call(onFinally, .undefined, [])
            let pr = try object.PromiseResolve(c, result)
            let valueThunk = r.Function("", 0) { _, _, _ in return v }
            return try object.Invoke(.object(pr), key("then"), [.object(valueThunk)])
        }
        let catchFinally = r.Function("", 1) { _, a, _ in
            let reason = object.Arg(a, 0)
            let result = try object.Call(onFinally, .undefined, [])
            let pr = try object.PromiseResolve(c, result)
            let thrower = r.Function("", 0) { _, _, _ in throw object.Completion.thrown(reason) }
            return try object.Invoke(.object(pr), key("then"), [.object(thrower)])
        }
        return try object.Invoke(thisV, key("then"), [.object(thenFinally), .object(catchFinally)])
    }

    r.Method(ctor, "resolve", 1) { thisV, args, _ in
        guard case .object(let c) = thisV else { throw object.ThrowTypeError("PromiseResolve called on non-object") }
        return .object(try object.PromiseResolve(c, object.Arg(args, 0)))
    }
    r.Method(ctor, "reject", 1) { thisV, args, _ in
        let cap = try object.NewPromiseCapability(thisV)
        _ = try object.Call(cap.Reject, .undefined, [object.Arg(args, 0)])
        return .object(cap.Promise)
    }
    r.Method(ctor, "withResolvers", 0) { thisV, _, _ in
        let cap = try object.NewPromiseCapability(thisV)
        let o = object.JSObject(proto: r.ObjectPrototype)
        try object.CreateDataPropertyOrThrow(o, key("promise"), .object(cap.Promise))
        try object.CreateDataPropertyOrThrow(o, key("resolve"), cap.Resolve)
        try object.CreateDataPropertyOrThrow(o, key("reject"), cap.Reject)
        return .object(o)
    }
    r.Method(ctor, "try", 1) { thisV, args, _ in
        guard case .object = thisV else { throw object.ThrowTypeError("Promise.try called on non-object") }
        let cap = try object.NewPromiseCapability(thisV)
        var rest: [Value] = []
        var i = 1
        while i < args.count { rest.append(args[i]); i += 1 }
        do {
            let v = try object.Call(object.Arg(args, 0), .undefined, rest)
            _ = try object.Call(cap.Resolve, .undefined, [v])
        } catch {
            guard let v = thrown(error) else { throw error }
            _ = try object.Call(cap.Reject, .undefined, [v])
        }
        return .object(cap.Promise)
    }

    combinator(r, ctor, "all") { cap, count, index, _ in
        let resolveElement = once(r) { v in
            count.values[index] = v
            count.n -= 1
            if count.n == 0 {
                _ = try object.Call(cap.Resolve, .undefined, [.object(object.CreateArrayFromList(r, count.values))])
            }
        }
        return (resolveElement, cap.Reject)
    }
    combinator(r, ctor, "allSettled") { cap, count, index, _ in
        var called = false
        let settle: (string, string) -> Value = { status, field in
            return .object(r.Function("", 1) { _, a, _ in
                if called { return .undefined }
                called = true
                let o = object.JSObject(proto: r.ObjectPrototype)
                try object.CreateDataPropertyOrThrow(o, key("status"), .string(str.Name(status)))
                try object.CreateDataPropertyOrThrow(o, key(field), object.Arg(a, 0))
                count.values[index] = .object(o)
                count.n -= 1
                if count.n == 0 {
                    _ = try object.Call(cap.Resolve, .undefined, [.object(object.CreateArrayFromList(r, count.values))])
                }
                return .undefined
            })
        }
        return (settle("fulfilled", "value"), settle("rejected", "reason"))
    }
    combinator(r, ctor, "any") { cap, count, index, _ in
        let rejectElement = once(r) { v in
            count.values[index] = v
            count.n -= 1
            if count.n == 0 {
                let e = object.MakeError(r.AggregateErrorPrototype, str.Name("All promises were rejected"))
                e.DefineData(key("errors"), .object(object.CreateArrayFromList(r, count.values)), writable: true, enumerable: false, configurable: true)
                _ = try object.Call(cap.Reject, .undefined, [.object(e)])
            }
        }
        return (cap.Resolve, rejectElement)
    }
    combinator(r, ctor, "race") { cap, _, _, _ in
        return (cap.Resolve, cap.Reject)
    }
}

/// once is a resolve element function: it acts on its first call only.
func once(_ r: object.Realm, _ body: @escaping (Value) throws -> Void) -> Value {
    var called = false
    return .object(r.Function("", 1) { _, a, _ in
        if called { return .undefined }
        called = true
        try body(object.Arg(a, 0))
        return .undefined
    })
}

/// combinator installs one of Promise.all/allSettled/any/race: the shared
/// iteration of §27.2.4.1.1 and friends, with `handlers` making the
/// then-arguments for the element at an index.
func combinator(_ r: object.Realm, _ ctor: object.JSObject, _ name: string,
                _ handlers: @escaping (object.PromiseCapability, Counter, int, Value) throws -> (Value, Value)) {
    r.Method(ctor, name, 1) { thisV, args, _ in
        let cap = try object.NewPromiseCapability(thisV)
        guard case .object(let c) = thisV else { return .object(cap.Promise) }
        var rec: object.IteratorRecord? = nil
        do {
            let resolveFn = try c.Get(key("resolve"), thisV)
            if !resolveFn.IsCallable { throw object.ThrowTypeError("Promise resolve or reject function is not callable") }
            rec = try object.GetIterator(object.Arg(args, 0))
            let count = Counter()
            var index = 0
            while let v = try object.IteratorStepValue(rec!) {
                count.values.append(.undefined)
                let next = try object.Call(resolveFn, thisV, [v])
                let (onF, onR) = try handlers(cap, count, index, next)
                count.n += 1
                _ = try object.Invoke(next, key("then"), [onF, onR])
                index += 1
            }
            count.n -= 1
            if count.n == 0 {
                if name == "all" || name == "allSettled" {
                    _ = try object.Call(cap.Resolve, .undefined, [.object(object.CreateArrayFromList(r, count.values))])
                } else if name == "any" {
                    let e = object.MakeError(r.AggregateErrorPrototype, str.Name("All promises were rejected"))
                    e.DefineData(key("errors"), .object(object.CreateArrayFromList(r, count.values)), writable: true, enumerable: false, configurable: true)
                    _ = try object.Call(cap.Reject, .undefined, [.object(e)])
                }
            }
        } catch {
            guard let v = thrown(error) else { throw error }
            if let it = rec, !it.Done { object.IteratorCloseOnThrow(it) }
            _ = try object.Call(cap.Reject, .undefined, [v])
        }
        return .object(cap.Promise)
    }
}

// MARK: function kinds (§27.3, §27.4, §27.7)

func installFunctionKinds(_ r: object.Realm) {
    let gfp = r.GeneratorFunctionPrototype
    let agfp = r.AsyncGeneratorFunctionPrototype
    let afp = r.AsyncFunctionPrototype
    let fc = r.FunctionConstructor!

    let gf = r.Constructor("GeneratorFunction", 1, prototype: gfp, global: false) { _, args, nt in
        return .object(try r.Engine!.CreateDynamicFunction(r, args, nt, isAsync: false, isGenerator: true))
    }
    let agf = r.Constructor("AsyncGeneratorFunction", 1, prototype: agfp, global: false) { _, args, nt in
        return .object(try r.Engine!.CreateDynamicFunction(r, args, nt, isAsync: true, isGenerator: true))
    }
    let af = r.Constructor("AsyncFunction", 1, prototype: afp, global: false) { _, args, nt in
        return .object(try r.Engine!.CreateDynamicFunction(r, args, nt, isAsync: true, isGenerator: false))
    }
    for c in [gf, agf, af] {
        c.Proto = fc
        // The prototype property of these constructors is not writable
        // and their prototypes' constructor is not writable either.
        c.DefineData(key("prototype"), c.OwnSlot(key("prototype"))!.Value, writable: false, enumerable: false, configurable: false)
    }
    r.Intrinsics["GeneratorFunction"] = gf
    r.Intrinsics["AsyncGeneratorFunction"] = agf
    r.Intrinsics["AsyncFunction"] = af
    gfp.DefineData(key("constructor"), .object(gf), writable: false, enumerable: false, configurable: true)
    agfp.DefineData(key("constructor"), .object(agf), writable: false, enumerable: false, configurable: true)
    afp.DefineData(key("constructor"), .object(af), writable: false, enumerable: false, configurable: true)
    gfp.DefineData(key("prototype"), .object(r.GeneratorPrototype), writable: false, enumerable: false, configurable: true)
    agfp.DefineData(key("prototype"), .object(r.AsyncGeneratorPrototype), writable: false, enumerable: false, configurable: true)
    r.GeneratorPrototype.DefineData(key("constructor"), .object(gfp), writable: false, enumerable: false, configurable: true)
    r.AsyncGeneratorPrototype.DefineData(key("constructor"), .object(agfp), writable: false, enumerable: false, configurable: true)
    gfp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("GeneratorFunction")), writable: false, enumerable: false, configurable: true)
    agfp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("AsyncGeneratorFunction")), writable: false, enumerable: false, configurable: true)
    afp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("AsyncFunction")), writable: false, enumerable: false, configurable: true)
}
