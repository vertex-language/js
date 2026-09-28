package object

import (
    "js/value"
)

/// IteratorRecord is the spec's Iterator Record (§7.4.1).
public final class IteratorRecord {
    public let Iterator: JSObject
    public let NextMethod: Value
    public var Done: bool = false

    public init(iterator: JSObject, next: Value) {
        self.Iterator = iterator
        self.NextMethod = next
    }
}

/// GetIteratorFromMethod (§7.4.2).
public func GetIteratorFromMethod(_ obj: Value, _ method: Value) throws -> IteratorRecord {
    let it = try Call(method, obj, [])
    guard case .object(let io) = it else {
        throw ThrowTypeError("Result of the Symbol.iterator method is not an object")
    }
    let next = try io.Get(keyNext, it)
    return IteratorRecord(iterator: io, next: next)
}

/// GetIterator (§7.4.3) for sync iteration.
public func GetIterator(_ obj: Value) throws -> IteratorRecord {
    let m = try GetMethodForIterator(obj, .symbol(value.SymIterator))
    if m.IsUndefined {
        throw ThrowTypeError("\(DescribeIterable(obj)) is not iterable")
    }
    return try GetIteratorFromMethod(obj, m)
}

/// GetAsyncIterator is GetIterator(obj, async): a sync iterator is wrapped
/// in an async-from-sync iterator.
public func GetAsyncIterator(_ obj: Value) throws -> IteratorRecord {
    let m = try GetMethodForIterator(obj, .symbol(value.SymAsyncIterator))
    if m.IsUndefined {
        let sm = try GetMethodForIterator(obj, .symbol(value.SymIterator))
        if sm.IsUndefined {
            throw ThrowTypeError("\(DescribeIterable(obj)) is not async iterable")
        }
        let sync = try GetIteratorFromMethod(obj, sm)
        return CreateAsyncFromSyncIterator(sync)
    }
    return try GetIteratorFromMethod(obj, m)
}

func GetMethodForIterator(_ obj: Value, _ key: PropertyKey) throws -> Value {
    if obj.IsNullish || obj.IsEmpty {
        return .undefined
    }
    let f = try GetV(obj, key)
    if f.IsNullish { return .undefined }
    if !f.IsCallable { throw ThrowTypeError("\(DescribeIterable(obj)) is not iterable") }
    return f
}

/// DescribeIterable names a value in "x is not iterable" as V8 does.
public func DescribeIterable(_ v: Value) -> string {
    switch v {
    case .undefined, .empty: return "undefined"
    case .null: return "null"
    case .object(let o):
        if o.IsCallable { return Describe(v) }
        return "object"
    case .string(let s): return "\"" + s.String + "\""
    default: return Describe(v)
    }
}

/// IteratorNext (§7.4.4).
public func IteratorNext(_ r: IteratorRecord, _ v: Value? = nil) throws -> JSObject {
    let res = v == nil ? try Call(r.NextMethod, .object(r.Iterator), []) : try Call(r.NextMethod, .object(r.Iterator), [v!])
    guard case .object(let o) = res else {
        throw ThrowTypeError("Iterator result \(Describe(res)) is not an object")
    }
    return o
}

/// IteratorComplete (§7.4.5).
public func IteratorComplete(_ o: JSObject) throws -> bool {
    return try o.Get(keyDone, .object(o)).Truthy
}

/// IteratorValue (§7.4.6).
public func IteratorValue(_ o: JSObject) throws -> Value {
    return try o.Get(keyValue, .object(o))
}

/// IteratorStepValue (§7.4.8): the next value, or nil when done.
public func IteratorStepValue(_ r: IteratorRecord) throws -> Value? {
    let res: JSObject
    do {
        res = try IteratorNext(r)
    } catch {
        r.Done = true
        throw error
    }
    let done: bool
    do {
        done = try IteratorComplete(res)
    } catch {
        r.Done = true
        throw error
    }
    if done {
        r.Done = true
        return nil
    }
    do {
        return try IteratorValue(res)
    } catch {
        r.Done = true
        throw error
    }
}

/// IteratorClose (§7.4.9) for a normal completion: errors from return
/// propagate, and a non-object result is a TypeError.
public func IteratorClose(_ r: IteratorRecord) throws {
    let ret = try GetMethod(.object(r.Iterator), keyReturn)
    if ret.IsUndefined { return }
    let res = try Call(ret, .object(r.Iterator), [])
    if !res.IsObject {
        throw ThrowTypeError("iterator.return() did not return an object")
    }
}

/// IteratorCloseOnThrow is IteratorClose for a throw completion: the
/// original exception wins over anything return does.
public func IteratorCloseOnThrow(_ r: IteratorRecord) {
    do {
        let ret = try GetMethod(.object(r.Iterator), keyReturn)
        if ret.IsUndefined { return }
        _ = try Call(ret, .object(r.Iterator), [])
    } catch {
    }
}

/// CreateIterResultObject (§7.4.14).
public func CreateIterResultObject(_ v: Value, _ done: bool) -> JSObject {
    let o = JSObject(proto: CurrentRealm().ObjectPrototype)
    o.DefineData(keyValue, v)
    o.DefineData(keyDone, .bool(done))
    return o
}

/// IterableToList (§7.4.15).
public func IterableToList(_ items: Value) throws -> [Value] {
    // Fast path: a plain array with the built-in iterator.
    if case .object(let o) = items, let a = o as? ArrayObject, a.IsDenseSimple, isPristineArrayIteration(a) {
        var out = a.Dense
        var i = 0
        while i < out.count {
            if out[i].IsEmpty { out[i] = .undefined }
            i += 1
        }
        return out
    }
    let r = try GetIterator(items)
    var out: [Value] = []
    while let v = try IteratorStepValue(r) {
        out.append(v)
    }
    return out
}

/// isPristineArrayIteration says an array iterates as the built-in array
/// iterator would, so its elements can be read directly.
public func isPristineArrayIteration(_ a: ArrayObject) -> bool {
    let r = CurrentRealm()
    guard a.Proto === r.ArrayPrototype else { return false }
    if a.find(.symbol(value.SymIterator)) >= 0 { return false }
    guard let iterFn = r.Intrinsics["ArrayValues"] else { return false }
    let s = r.ArrayPrototype.find(.symbol(value.SymIterator))
    if s < 0 { return false }
    guard case .object(let f) = r.ArrayPrototype.slots[s].Value, f === iterFn else { return false }
    guard let nextFn = r.Intrinsics["ArrayIteratorNext"] else { return false }
    let n = r.ArrayIteratorPrototype.find(keyNext)
    if n < 0 { return false }
    guard case .object(let nf) = r.ArrayIteratorPrototype.slots[n].Value, nf === nextFn else { return false }
    return true
}

/// AsyncFromSyncIterator is §27.1.6's wrapper: its methods live on
/// %AsyncFromSyncIteratorPrototype%, installed by the built-ins.
public final class AsyncFromSyncIterator: JSObject {
    public let Sync: IteratorRecord
    public init(_ sync: IteratorRecord, proto: JSObject) {
        self.Sync = sync
        super.init(proto: proto)
    }
}

public func CreateAsyncFromSyncIterator(_ sync: IteratorRecord) -> IteratorRecord {
    let r = CurrentRealm()
    let o = AsyncFromSyncIterator(sync, proto: r.AsyncFromSyncIteratorPrototype)
    let next = (try? o.Get(keyNext, .object(o))) ?? .undefined
    return IteratorRecord(iterator: o, next: next)
}
