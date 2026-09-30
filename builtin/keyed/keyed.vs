// Package keyed installs the keyed collections (ECMA-262 §24): Map, Set,
// WeakMap and WeakSet, with their iterators.
package keyed

import (
    "js/builtin/fundamental"
    "js/object"
    "js/str"
    "js/value"
)

typealias Value = object.Value

func key(_ s: string) -> value.PropertyKey { return value.PropertyKey.Named(s) }

// MARK: the table

/// Key is a value as a hash key under SameValueZero: -0 is +0, every NaN
/// is one NaN, objects and symbols are themselves.
public struct Key: Hashable {
    let kind: int
    let bits: uint64
    let text: str.JSString?

    public init(_ v: Value) {
        switch v {
        case .number(let d):
            var n = d
            if n == 0 { n = 0 }
            kind = 1
            bits = n.isNaN ? 0x7FF8000000000000 : n.bitPattern
            text = nil
        case .string(let s):
            kind = 2
            bits = 0
            text = s
        case .bool(let b):
            kind = 3
            bits = b ? 1 : 0
            text = nil
        case .null:
            kind = 4
            bits = 0
            text = nil
        case .symbol(let s):
            kind = 5
            bits = uint64(s.ID)
            text = nil
        case .object(let o):
            kind = 6
            bits = uint64(o.Serial)
            text = nil
        case .bigint(let b):
            kind = 7
            bits = 0
            text = b.JSString
        default:
            kind = 0
            bits = 0
            text = nil
        }
    }

    public static func ==(a: Key, b: Key) -> bool {
        if a.kind != b.kind || a.bits != b.bits { return false }
        if let x = a.text, let y = b.text { return x.Equals(y) }
        return a.text == nil && b.text == nil
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(bits)
        if let t = text { hasher.combine(t.HashCode) }
    }
}

/// Table is a Map's or Set's entries: insertion ordered, with deleted
/// entries left as .empty so that iterators keep their place. When it
/// compacts, it records the removed positions so an iterator can move
/// its index to where the entry went.
public final class Table {
    public var Keys: [Value] = []
    public var Values: [Value] = []
    var index: [Key: int] = [:]
    public var Size: int = 0
    var removed: [[int]] = []

    public init() {}

    /// Epoch counts compactions; an iterator remembers the one it saw.
    public var Epoch: int { return removed.count }

    public func Find(_ k: Value) -> int {
        return index[Key(k)] ?? -1
    }

    public func Get(_ k: Value) -> Value? {
        let i = Find(k)
        return i < 0 ? nil : Values[i]
    }

    public func Has(_ k: Value) -> bool { return Find(k) >= 0 }

    public func Set(_ k: Value, _ v: Value) {
        var kk = k
        if case .number(let d) = k, d == 0 { kk = .number(0) }
        let hk = Key(kk)
        if let i = index[hk] {
            Values[i] = v
            return
        }
        index[hk] = Keys.count
        Keys.append(kk)
        Values.append(v)
        Size += 1
    }

    public func Delete(_ k: Value) -> bool {
        let hk = Key(k)
        guard let i = index[hk] else { return false }
        index[hk] = nil
        Keys[i] = .empty
        Values[i] = .empty
        Size -= 1
        if Keys.count > 32 && Size * 2 < Keys.count { compact() }
        return true
    }

    public func Clear() {
        var i = 0
        while i < Keys.count {
            Keys[i] = .empty
            Values[i] = .empty
            i += 1
        }
        index = [:]
        Size = 0
        compact()
    }

    func compact() {
        var gone: [int] = []
        var nk: [Value] = []
        var nv: [Value] = []
        var i = 0
        while i < Keys.count {
            if Keys[i].IsEmpty {
                gone.append(i)
            } else {
                index[Key(Keys[i])] = nk.count
                nk.append(Keys[i])
                nv.append(Values[i])
            }
            i += 1
        }
        Keys = nk
        Values = nv
        removed.append(gone)
    }

    /// Remap moves an iterator's index from the epoch it saw to now.
    public func Remap(_ i: int, from epoch: int) -> int {
        var at = i
        var e = epoch
        while e < removed.count {
            var before = 0
            for g in removed[e] where g < at { before += 1 }
            at -= before
            e += 1
        }
        return at
    }
}

/// Collection is a Map or Set instance.
public final class Collection: object.JSObject {
    public let Entries = Table()
    public let IsMap: bool

    public init(isMap: bool, proto: object.JSObject) {
        self.IsMap = isMap
        super.init(proto: proto)
        self.Kind = isMap ? .map : .set
    }
}

/// WeakCollection is a WeakMap or WeakSet.
///
/// TODO(gc): its keys are held strongly until the engine has a tracing
/// collector; then each entry becomes an ephemeron, whose value lives only
/// while its key does.
public final class WeakCollection: object.JSObject {
    public let Entries = Table()
    public let IsMap: bool

    public init(isMap: bool, proto: object.JSObject) {
        self.IsMap = isMap
        super.init(proto: proto)
        self.Kind = isMap ? .weakMap : .weakSet
    }
}

/// CanBeHeldWeakly (§9.13).
public func CanBeHeldWeakly(_ v: Value) -> bool {
    if case .object = v { return true }
    if case .symbol(let s) = v { return s.RegistryKey == nil }
    return false
}

// MARK: install

public func Install(_ r: object.Realm) {
    installMap(r)
    installSet(r)
    installWeak(r)
}

func thisCollection(_ v: Value, map: bool, _ method: string) throws -> Collection {
    if case .object(let o) = v, let c = o as? Collection, c.IsMap == map { return c }
    let kind = map ? "Map" : "Set"
    throw object.ThrowTypeError("Method \(kind).prototype.\(method) called on incompatible receiver \(object.Describe(v))")
}

/// fill is the constructors' AddEntriesFromIterable (§24.1.1.2) and the
/// Set constructor's loop, calling the (possibly replaced) adder.
func fill(_ target: object.JSObject, _ iterable: Value, adderName: string, pairs: bool) throws {
    if iterable.IsNullish { return }
    let adder = try target.Get(key(adderName), .object(target))
    if !adder.IsCallable { throw object.ThrowTypeError("'\(object.Describe(adder))' returned for property '\(adderName)' of object '\(object.Describe(.object(target)))' is not a function") }
    let rec = try object.GetIterator(iterable)
    while let next = try object.IteratorStepValue(rec) {
        do {
            if pairs {
                guard case .object(let eo) = next else {
                    throw object.ThrowTypeError("Iterator value \(object.Describe(next)) is not an entry object")
                }
                let k = try eo.Get(.index(0), next)
                let v = try eo.Get(.index(1), next)
                _ = try object.Call(adder, .object(target), [k, v])
            } else {
                _ = try object.Call(adder, .object(target), [next])
            }
        } catch {
            object.IteratorCloseOnThrow(rec)
            throw error
        }
    }
}

// MARK: iterators

public enum IterationKind {
    case keys
    case values
    case entries
}

public final class CollectionIterator: object.JSObject {
    public var Target: Collection?
    public var Index: int = 0
    public var Epoch: int
    public let Mode: IterationKind

    public init(_ c: Collection, _ mode: IterationKind, proto: object.JSObject) {
        self.Target = c
        self.Mode = mode
        self.Epoch = c.Entries.Epoch
        super.init(proto: proto)
    }
}

func iteratorPrototype(_ r: object.Realm, _ name: string, map: bool) -> object.JSObject {
    let p = object.JSObject(proto: r.IteratorPrototype)
    r.Method(p, "next", 0) { thisV, _, _ in
        guard case .object(let o) = thisV, let it = o as? CollectionIterator, it.Target?.IsMap ?? map == map else {
            throw object.ThrowTypeError("Method \(name).prototype.next called on incompatible receiver \(object.Describe(thisV))")
        }
        guard let c = it.Target else { return .object(object.CreateIterResultObject(.undefined, true)) }
        let t = c.Entries
        if it.Epoch != t.Epoch {
            it.Index = t.Remap(it.Index, from: it.Epoch)
            it.Epoch = t.Epoch
        }
        while it.Index < t.Keys.count {
            let i = it.Index
            it.Index += 1
            let k = t.Keys[i]
            if k.IsEmpty { continue }
            switch it.Mode {
            case .keys:
                return .object(object.CreateIterResultObject(k, false))
            case .values:
                return .object(object.CreateIterResultObject(t.Values[i], false))
            case .entries:
                let pair = object.CreateArrayFromList(r, [k, t.Values[i]])
                return .object(object.CreateIterResultObject(.object(pair), false))
            }
        }
        it.Target = nil
        return .object(object.CreateIterResultObject(.undefined, true))
    }
    p.DefineData(.symbol(value.SymToStringTag), .string(str.Name(name)), writable: false, enumerable: false, configurable: true)
    return p
}

// MARK: Map (§24.1)

func installMap(_ r: object.Realm) {
    let mp = r.MapPrototype
    let ctor = r.Constructor("Map", 0, prototype: mp) { _, args, nt in
        guard let n = nt else { throw object.ThrowTypeError("Constructor Map requires 'new'") }
        let proto = try object.GetPrototypeFromConstructor(n, r.MapPrototype)
        let m = Collection(isMap: true, proto: proto)
        try fill(m, object.Arg(args, 0), adderName: "set", pairs: true)
        return .object(m)
    }
    r.Getter(ctor, .symbol(value.SymSpecies)) { thisV, _, _ in return thisV }
    r.Method(ctor, "groupBy", 2) { _, args, _ in
        let groups = try fundamental.groupBy(object.Arg(args, 0), object.Arg(args, 1), propertyKeys: false)
        let m = Collection(isMap: true, proto: r.MapPrototype)
        for (k, list) in groups {
            m.Entries.Set(k, .object(object.CreateArrayFromList(r, list)))
        }
        return .object(m)
    }
    r.Method(mp, "get", 1) { thisV, args, _ in
        let m = try thisCollection(thisV, map: true, "get")
        return m.Entries.Get(object.Arg(args, 0)) ?? .undefined
    }
    r.Method(mp, "set", 2) { thisV, args, _ in
        let m = try thisCollection(thisV, map: true, "set")
        m.Entries.Set(object.Arg(args, 0), object.Arg(args, 1))
        return thisV
    }
    r.Method(mp, "has", 1) { thisV, args, _ in
        return .bool(try thisCollection(thisV, map: true, "has").Entries.Has(object.Arg(args, 0)))
    }
    r.Method(mp, "delete", 1) { thisV, args, _ in
        return .bool(try thisCollection(thisV, map: true, "delete").Entries.Delete(object.Arg(args, 0)))
    }
    r.Method(mp, "clear", 0) { thisV, _, _ in
        try thisCollection(thisV, map: true, "clear").Entries.Clear()
        return .undefined
    }
    r.Method(mp, "getOrInsert", 2) { thisV, args, _ in
        let m = try thisCollection(thisV, map: true, "getOrInsert")
        if let v = m.Entries.Get(object.Arg(args, 0)) { return v }
        m.Entries.Set(object.Arg(args, 0), object.Arg(args, 1))
        return object.Arg(args, 1)
    }
    r.Method(mp, "getOrInsertComputed", 2) { thisV, args, _ in
        let m = try thisCollection(thisV, map: true, "getOrInsertComputed")
        let cb = object.Arg(args, 1)
        if !cb.IsCallable { throw object.ThrowTypeError("\(object.Describe(cb)) is not a function") }
        var k = object.Arg(args, 0)
        if case .number(let d) = k, d == 0 { k = .number(0) }
        if let v = m.Entries.Get(k) { return v }
        let v = try object.Call(cb, .undefined, [k])
        m.Entries.Set(k, v)
        return v
    }
    r.Method(mp, "forEach", 1) { thisV, args, _ in
        let m = try thisCollection(thisV, map: true, "forEach")
        let cb = object.Arg(args, 0)
        if !cb.IsCallable { throw object.ThrowTypeError("\(object.Describe(cb)) is not a function") }
        try forEach(m, cb, object.Arg(args, 1))
        return .undefined
    }
    r.Getter(mp, key("size")) { thisV, _, _ in
        return .number(float64(try thisCollection(thisV, map: true, "size").Entries.Size))
    }
    let mip = iteratorPrototype(r, "Map Iterator", map: true)
    r.Intrinsics["MapIteratorPrototype"] = mip
    let entries = r.Function("entries", 0) { thisV, _, _ in
        return .object(CollectionIterator(try thisCollection(thisV, map: true, "entries"), .entries, proto: mip))
    }
    mp.DefineData(key("entries"), .object(entries), writable: true, enumerable: false, configurable: true)
    mp.DefineData(.symbol(value.SymIterator), .object(entries), writable: true, enumerable: false, configurable: true)
    r.Method(mp, "keys", 0) { thisV, _, _ in
        return .object(CollectionIterator(try thisCollection(thisV, map: true, "keys"), .keys, proto: mip))
    }
    r.Method(mp, "values", 0) { thisV, _, _ in
        return .object(CollectionIterator(try thisCollection(thisV, map: true, "values"), .values, proto: mip))
    }
    mp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("Map")), writable: false, enumerable: false, configurable: true)
}

func forEach(_ c: Collection, _ cb: Value, _ thisArg: Value) throws {
    let t = c.Entries
    var i = 0
    var epoch = t.Epoch
    while true {
        if epoch != t.Epoch {
            i = t.Remap(i, from: epoch)
            epoch = t.Epoch
        }
        if i >= t.Keys.count { break }
        let k = t.Keys[i]
        let v = t.Values[i]
        i += 1
        if k.IsEmpty { continue }
        _ = try object.Call(cb, thisArg, [c.IsMap ? v : k, k, .object(c)])
    }
}

// MARK: Set (§24.2)

/// SetRecord is GetSetRecord's result (§24.2.1.2).
struct SetRecord {
    let set: object.JSObject
    let size: float64
    let has: Value
    let keys: Value
}

func getSetRecord(_ v: Value) throws -> SetRecord {
    guard case .object(let o) = v else { throw object.ThrowTypeError("\(object.Describe(v)) is not an object") }
    let rawSize = try o.Get(key("size"), v)
    let num = try object.ToNumber(rawSize)
    if num.isNaN { throw object.ThrowTypeError("The 'size' property must be a number") }
    let size = value.ToIntegerOrInfinity(num)
    if size < 0 { throw object.ThrowRangeError("'\(value.NumberToString(size))' is an invalid size") }
    let has = try o.Get(key("has"), v)
    if !has.IsCallable { throw object.ThrowTypeError("The 'has' property must be a function") }
    let keys = try o.Get(key("keys"), v)
    if !keys.IsCallable { throw object.ThrowTypeError("The 'keys' property must be a function") }
    return SetRecord(set: o, size: size, has: has, keys: keys)
}

func keysIterator(_ rec: SetRecord) throws -> object.IteratorRecord {
    let it = try object.Call(rec.keys, .object(rec.set), [])
    guard case .object(let io) = it else { throw object.ThrowTypeError("keys() did not return an object") }
    return object.IteratorRecord(iterator: io, next: try io.Get(key("next"), it))
}

func liveKeys(_ c: Collection) -> [Value] {
    var out: [Value] = []
    for k in c.Entries.Keys where !k.IsEmpty { out.append(k) }
    return out
}

func installSet(_ r: object.Realm) {
    let sp = r.SetPrototype
    let ctor = r.Constructor("Set", 0, prototype: sp) { _, args, nt in
        guard let n = nt else { throw object.ThrowTypeError("Constructor Set requires 'new'") }
        let proto = try object.GetPrototypeFromConstructor(n, r.SetPrototype)
        let s = Collection(isMap: false, proto: proto)
        try fill(s, object.Arg(args, 0), adderName: "add", pairs: false)
        return .object(s)
    }
    r.Getter(ctor, .symbol(value.SymSpecies)) { thisV, _, _ in return thisV }
    func newSet(_ keys: [Value]) -> Collection {
        let s = Collection(isMap: false, proto: r.SetPrototype)
        for k in keys { s.Entries.Set(k, k) }
        return s
    }
    r.Method(sp, "add", 1) { thisV, args, _ in
        let s = try thisCollection(thisV, map: false, "add")
        let v = object.Arg(args, 0)
        if !s.Entries.Has(v) { s.Entries.Set(v, v) }
        return thisV
    }
    r.Method(sp, "has", 1) { thisV, args, _ in
        return .bool(try thisCollection(thisV, map: false, "has").Entries.Has(object.Arg(args, 0)))
    }
    r.Method(sp, "delete", 1) { thisV, args, _ in
        return .bool(try thisCollection(thisV, map: false, "delete").Entries.Delete(object.Arg(args, 0)))
    }
    r.Method(sp, "clear", 0) { thisV, _, _ in
        try thisCollection(thisV, map: false, "clear").Entries.Clear()
        return .undefined
    }
    r.Method(sp, "forEach", 1) { thisV, args, _ in
        let s = try thisCollection(thisV, map: false, "forEach")
        let cb = object.Arg(args, 0)
        if !cb.IsCallable { throw object.ThrowTypeError("\(object.Describe(cb)) is not a function") }
        try forEach(s, cb, object.Arg(args, 1))
        return .undefined
    }
    r.Getter(sp, key("size")) { thisV, _, _ in
        return .number(float64(try thisCollection(thisV, map: false, "size").Entries.Size))
    }
    r.Method(sp, "union", 1) { thisV, args, _ in
        let s = try thisCollection(thisV, map: false, "union")
        let other = try getSetRecord(object.Arg(args, 0))
        let it = try keysIterator(other)
        let out = newSet(liveKeys(s))
        while let k = try object.IteratorStepValue(it) {
            if !out.Entries.Has(k) { out.Entries.Set(k, k) }
        }
        return .object(out)
    }
    r.Method(sp, "intersection", 1) { thisV, args, _ in
        let s = try thisCollection(thisV, map: false, "intersection")
        let other = try getSetRecord(object.Arg(args, 0))
        let out = newSet([])
        if float64(s.Entries.Size) <= other.size {
            for k in liveKeys(s) {
                if try object.Call(other.has, .object(other.set), [k]).Truthy {
                    if !out.Entries.Has(k) { out.Entries.Set(k, k) }
                }
            }
        } else {
            let it = try keysIterator(other)
            while let k = try object.IteratorStepValue(it) {
                if s.Entries.Has(k) && !out.Entries.Has(k) { out.Entries.Set(k, k) }
            }
        }
        return .object(out)
    }
    r.Method(sp, "difference", 1) { thisV, args, _ in
        let s = try thisCollection(thisV, map: false, "difference")
        let other = try getSetRecord(object.Arg(args, 0))
        let out = newSet(liveKeys(s))
        if float64(s.Entries.Size) <= other.size {
            for k in liveKeys(s) {
                if try object.Call(other.has, .object(other.set), [k]).Truthy { _ = out.Entries.Delete(k) }
            }
        } else {
            let it = try keysIterator(other)
            while let k = try object.IteratorStepValue(it) { _ = out.Entries.Delete(k) }
        }
        return .object(out)
    }
    r.Method(sp, "symmetricDifference", 1) { thisV, args, _ in
        let s = try thisCollection(thisV, map: false, "symmetricDifference")
        let other = try getSetRecord(object.Arg(args, 0))
        let it = try keysIterator(other)
        let out = newSet(liveKeys(s))
        while let k = try object.IteratorStepValue(it) {
            if s.Entries.Has(k) { _ = out.Entries.Delete(k) } else if !out.Entries.Has(k) { out.Entries.Set(k, k) }
        }
        return .object(out)
    }
    r.Method(sp, "isSubsetOf", 1) { thisV, args, _ in
        let s = try thisCollection(thisV, map: false, "isSubsetOf")
        let other = try getSetRecord(object.Arg(args, 0))
        if float64(s.Entries.Size) > other.size { return .bool(false) }
        for k in liveKeys(s) {
            if !(try object.Call(other.has, .object(other.set), [k]).Truthy) { return .bool(false) }
        }
        return .bool(true)
    }
    r.Method(sp, "isSupersetOf", 1) { thisV, args, _ in
        let s = try thisCollection(thisV, map: false, "isSupersetOf")
        let other = try getSetRecord(object.Arg(args, 0))
        if float64(s.Entries.Size) < other.size { return .bool(false) }
        let it = try keysIterator(other)
        while let k = try object.IteratorStepValue(it) {
            if !s.Entries.Has(k) {
                try object.IteratorClose(it)
                return .bool(false)
            }
        }
        return .bool(true)
    }
    r.Method(sp, "isDisjointFrom", 1) { thisV, args, _ in
        let s = try thisCollection(thisV, map: false, "isDisjointFrom")
        let other = try getSetRecord(object.Arg(args, 0))
        if float64(s.Entries.Size) <= other.size {
            for k in liveKeys(s) {
                if try object.Call(other.has, .object(other.set), [k]).Truthy { return .bool(false) }
            }
        } else {
            let it = try keysIterator(other)
            while let k = try object.IteratorStepValue(it) {
                if s.Entries.Has(k) {
                    try object.IteratorClose(it)
                    return .bool(false)
                }
            }
        }
        return .bool(true)
    }
    let sip = iteratorPrototype(r, "Set Iterator", map: false)
    r.Intrinsics["SetIteratorPrototype"] = sip
    let values = r.Function("values", 0) { thisV, _, _ in
        return .object(CollectionIterator(try thisCollection(thisV, map: false, "values"), .values, proto: sip))
    }
    sp.DefineData(key("values"), .object(values), writable: true, enumerable: false, configurable: true)
    sp.DefineData(key("keys"), .object(values), writable: true, enumerable: false, configurable: true)
    sp.DefineData(.symbol(value.SymIterator), .object(values), writable: true, enumerable: false, configurable: true)
    r.Method(sp, "entries", 0) { thisV, _, _ in
        return .object(CollectionIterator(try thisCollection(thisV, map: false, "entries"), .entries, proto: sip))
    }
    sp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("Set")), writable: false, enumerable: false, configurable: true)
}

// MARK: WeakMap and WeakSet (§24.3, §24.4)

func thisWeak(_ v: Value, map: bool, _ method: string) throws -> WeakCollection {
    if case .object(let o) = v, let c = o as? WeakCollection, c.IsMap == map { return c }
    let kind = map ? "WeakMap" : "WeakSet"
    throw object.ThrowTypeError("Method \(kind).prototype.\(method) called on incompatible receiver \(object.Describe(v))")
}

func installWeak(_ r: object.Realm) {
    let wmp = object.JSObject(proto: r.ObjectPrototype)
    let wsp = object.JSObject(proto: r.ObjectPrototype)
    _ = r.Constructor("WeakMap", 0, prototype: wmp) { _, args, nt in
        guard let n = nt else { throw object.ThrowTypeError("Constructor WeakMap requires 'new'") }
        let m = WeakCollection(isMap: true, proto: try object.GetPrototypeFromConstructor(n, wmp))
        try fill(m, object.Arg(args, 0), adderName: "set", pairs: true)
        return .object(m)
    }
    _ = r.Constructor("WeakSet", 0, prototype: wsp) { _, args, nt in
        guard let n = nt else { throw object.ThrowTypeError("Constructor WeakSet requires 'new'") }
        let s = WeakCollection(isMap: false, proto: try object.GetPrototypeFromConstructor(n, wsp))
        try fill(s, object.Arg(args, 0), adderName: "add", pairs: false)
        return .object(s)
    }
    r.Method(wmp, "get", 1) { thisV, args, _ in
        return try thisWeak(thisV, map: true, "get").Entries.Get(object.Arg(args, 0)) ?? .undefined
    }
    r.Method(wmp, "set", 2) { thisV, args, _ in
        let m = try thisWeak(thisV, map: true, "set")
        let k = object.Arg(args, 0)
        if !CanBeHeldWeakly(k) { throw object.ThrowTypeError("Invalid value used as weak map key") }
        m.Entries.Set(k, object.Arg(args, 1))
        return thisV
    }
    r.Method(wmp, "has", 1) { thisV, args, _ in
        return .bool(try thisWeak(thisV, map: true, "has").Entries.Has(object.Arg(args, 0)))
    }
    r.Method(wmp, "delete", 1) { thisV, args, _ in
        return .bool(try thisWeak(thisV, map: true, "delete").Entries.Delete(object.Arg(args, 0)))
    }
    r.Method(wmp, "getOrInsert", 2) { thisV, args, _ in
        let m = try thisWeak(thisV, map: true, "getOrInsert")
        let k = object.Arg(args, 0)
        if !CanBeHeldWeakly(k) { throw object.ThrowTypeError("Invalid value used as weak map key") }
        if let v = m.Entries.Get(k) { return v }
        m.Entries.Set(k, object.Arg(args, 1))
        return object.Arg(args, 1)
    }
    r.Method(wmp, "getOrInsertComputed", 2) { thisV, args, _ in
        let m = try thisWeak(thisV, map: true, "getOrInsertComputed")
        let k = object.Arg(args, 0)
        if !CanBeHeldWeakly(k) { throw object.ThrowTypeError("Invalid value used as weak map key") }
        let cb = object.Arg(args, 1)
        if !cb.IsCallable { throw object.ThrowTypeError("\(object.Describe(cb)) is not a function") }
        if let v = m.Entries.Get(k) { return v }
        let v = try object.Call(cb, .undefined, [k])
        m.Entries.Set(k, v)
        return v
    }
    wmp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("WeakMap")), writable: false, enumerable: false, configurable: true)
    r.Method(wsp, "add", 1) { thisV, args, _ in
        let s = try thisWeak(thisV, map: false, "add")
        let v = object.Arg(args, 0)
        if !CanBeHeldWeakly(v) { throw object.ThrowTypeError("Invalid value used in weak set") }
        s.Entries.Set(v, v)
        return thisV
    }
    r.Method(wsp, "has", 1) { thisV, args, _ in
        return .bool(try thisWeak(thisV, map: false, "has").Entries.Has(object.Arg(args, 0)))
    }
    r.Method(wsp, "delete", 1) { thisV, args, _ in
        return .bool(try thisWeak(thisV, map: false, "delete").Entries.Delete(object.Arg(args, 0)))
    }
    wsp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("WeakSet")), writable: false, enumerable: false, configurable: true)
}
