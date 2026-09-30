package object

import (
    "js/str"
    "js/value"
)

/// Completion is how an ECMAScript exception travels through Vertex code:
/// every internal method and abstract operation that can throw throws one,
/// carrying the thrown value. (A class, not an enum with a payload: vsc
/// can't yet put a payload enum declared here into an Error existential.)
public final class Completion: Error {
    public let Value: Value

    public init(_ v: Value) {
        self.Value = v
    }

    public static func thrown(_ v: Value) -> Completion {
        return Completion(v)
    }
}

/// PropertyDescriptor is the spec's Property Descriptor record: every
/// field may be absent.
public struct PropertyDescriptor {
    public var Value: Value?
    public var Writable: bool?
    public var Get: Value?
    public var Set: Value?
    public var Enumerable: bool?
    public var Configurable: bool?

    public init() {
        self.Value = nil
        self.Writable = nil
        self.Get = nil
        self.Set = nil
        self.Enumerable = nil
        self.Configurable = nil
    }

    /// Data makes a complete data descriptor.
    public static func Data(_ v: Value, writable: bool = true, enumerable: bool = true, configurable: bool = true) -> PropertyDescriptor {
        var d = PropertyDescriptor()
        d.Value = v
        d.Writable = writable
        d.Enumerable = enumerable
        d.Configurable = configurable
        return d
    }

    /// Accessor makes a complete accessor descriptor.
    public static func Accessor(get: Value, set: Value, enumerable: bool = false, configurable: bool = true) -> PropertyDescriptor {
        var d = PropertyDescriptor()
        d.Get = get
        d.Set = set
        d.Enumerable = enumerable
        d.Configurable = configurable
        return d
    }

    public var IsAccessor: bool { return Get != nil || Set != nil }
    public var IsData: bool { return Value != nil || Writable != nil }
    public var IsGeneric: bool { return !IsAccessor && !IsData }
}

/// Slot flags.
let fWritable: uint8 = 1
let fEnumerable: uint8 = 2
let fConfigurable: uint8 = 4
let fAccessor: uint8 = 8
let fDeleted: uint8 = 16

/// Slot is one stored property.
public struct Slot {
    public var Value: Value
    public var Getter: JSObject?
    public var Setter: JSObject?
    public var Flags: uint8

    public init(value: Value, flags: uint8) {
        self.Value = value
        self.Getter = nil
        self.Setter = nil
        self.Flags = flags
    }

    public var Writable: bool { return Flags & fWritable != 0 }
    public var Enumerable: bool { return Flags & fEnumerable != 0 }
    public var Configurable: bool { return Flags & fConfigurable != 0 }
    public var IsAccessor: bool { return Flags & fAccessor != 0 }

    public var Descriptor: PropertyDescriptor {
        var d = PropertyDescriptor()
        if IsAccessor {
            d.Get = Getter != nil ? .object(Getter!) : .undefined
            d.Set = Setter != nil ? .object(Setter!) : .undefined
        } else {
            d.Value = Value
            d.Writable = Writable
        }
        d.Enumerable = Enumerable
        d.Configurable = Configurable
        return d
    }
}

/// Kind is what built-in an object is, for the checks the spec makes on
/// internal slots and for Object.prototype.toString.
public enum Kind: Equatable {
    case ordinary
    case array
    case function
    case error
    case boolean
    case number
    case string
    case symbol
    case bigint
    case date
    case regexp
    case arguments
    case map
    case set
    case weakMap
    case weakSet
    case weakRef
    case finalizationRegistry
    case promise
    case proxy
    case arrayBuffer
    case sharedArrayBuffer
    case dataView
    case typedArray
    case generator
    case asyncGenerator
    case iterator
    case module
    case global
}

/// JSObject is an ECMAScript object. It is an ordinary object; exotic
/// objects (arrays, proxies, strings, arguments, typed arrays, functions)
/// subclass it and override internal methods.
var nextObjectSerial = 0

open class JSObject {
    public var Proto: JSObject?
    public var Extensible: bool = true
    public var Kind: Kind = .ordinary
    /// IsHTMLDDA marks the one object (document.all) that is falsy and typeof "undefined".
    public var IsHTMLDDA: bool = false
    /// PrimitiveValue is a wrapper's [[BooleanData]], [[NumberData]] and so
    /// on, or a Date's time value.
    public var PrimitiveValue: Value = .undefined

    var keys: [value.PropertyKey] = []
    var slots: [Slot] = []
    var index: [value.PropertyKey: int] = [:]
    var indexed: bool = false
    var deleted: int = 0
    var anyIndexKey: bool = false

    /// Serial is the object's identity as a number, unique in the process:
    /// what Map, Set and WeakMap hash an object key by.
    public let Serial: int

    public init(proto: JSObject?) {
        self.Proto = proto
        nextObjectSerial += 1
        self.Serial = nextObjectSerial
    }

    // MARK: storage

    /// find is the slot number of an own stored key, or -1.
    public func find(_ key: value.PropertyKey) -> int {
        if indexed {
            return index[key] ?? -1
        }
        let n = keys.count
        var i = 0
        switch key {
        case .string(let s):
            while i < n {
                if case .string(let t) = keys[i], (s === t || s.Equals(t)) {
                    return slots[i].Flags & fDeleted != 0 ? -1 : i
                }
                i += 1
            }
        case .index(let x):
            while i < n {
                if case .index(let y) = keys[i], x == y {
                    return slots[i].Flags & fDeleted != 0 ? -1 : i
                }
                i += 1
            }
        case .symbol(let s):
            while i < n {
                if case .symbol(let t) = keys[i], s === t {
                    return slots[i].Flags & fDeleted != 0 ? -1 : i
                }
                i += 1
            }
        }
        return -1
    }

    /// OwnSlot is the stored property for a key, if any.
    public func OwnSlot(_ key: value.PropertyKey) -> Slot? {
        let i = find(key)
        return i < 0 ? nil : slots[i]
    }

    /// store adds or replaces a stored property.
    public func store(_ key: value.PropertyKey, _ slot: Slot) {
        let i = find(key)
        if i >= 0 {
            slots[i] = slot
            return
        }
        keys.append(key)
        slots.append(slot)
        if case .index = key { anyIndexKey = true }
        if indexed {
            index[key] = keys.count - 1
        } else if keys.count > 8 {
            buildIndex()
        }
    }

    func buildIndex() {
        index = [:]
        var i = 0
        while i < keys.count {
            if slots[i].Flags & fDeleted == 0 { index[keys[i]] = i }
            i += 1
        }
        indexed = true
    }

    /// remove deletes a stored property.
    public func remove(_ key: value.PropertyKey) {
        let i = find(key)
        if i < 0 { return }
        slots[i] = Slot(value: .undefined, flags: fDeleted)
        deleted += 1
        if indexed {
            index[key] = nil
        }
        if deleted > 16 && deleted * 2 > keys.count {
            compact()
        }
    }

    func compact() {
        var nk: [value.PropertyKey] = []
        var ns: [Slot] = []
        var i = 0
        while i < keys.count {
            if slots[i].Flags & fDeleted == 0 {
                nk.append(keys[i])
                ns.append(slots[i])
            }
            i += 1
        }
        keys = nk
        slots = ns
        deleted = 0
        if keys.count > 8 {
            buildIndex()
        } else {
            indexed = false
            index = [:]
        }
    }

    /// DefineData adds a data property directly, for building built-ins
    /// and fresh objects: no checks.
    public func DefineData(_ key: value.PropertyKey, _ v: Value, writable: bool = true, enumerable: bool = true, configurable: bool = true) {
        var f: uint8 = 0
        if writable { f |= fWritable }
        if enumerable { f |= fEnumerable }
        if configurable { f |= fConfigurable }
        store(key, Slot(value: v, flags: f))
    }

    /// DefineAccessor adds an accessor property directly.
    public func DefineAccessorDirect(_ key: value.PropertyKey, getter: JSObject?, setter: JSObject?, enumerable: bool = false, configurable: bool = true) {
        var f: uint8 = fAccessor
        if enumerable { f |= fEnumerable }
        if configurable { f |= fConfigurable }
        var s = Slot(value: .undefined, flags: f)
        s.Getter = getter
        s.Setter = setter
        store(key, s)
    }

    /// StoredKeys are the own stored keys in insertion order.
    public var StoredKeys: [value.PropertyKey] {
        var out: [value.PropertyKey] = []
        var i = 0
        while i < keys.count {
            if slots[i].Flags & fDeleted == 0 { out.append(keys[i]) }
            i += 1
        }
        return out
    }

    /// hasIndexKeys says whether an index key was ever stored here.
    public func hasIndexKeys() -> bool { return anyIndexKey }

    /// StoredCount is the number of own stored properties.
    public var StoredCount: int { return keys.count - deleted }

    // MARK: internal methods (§10.1)

    open func GetPrototypeOf() throws -> JSObject? {
        return Proto
    }

    open func SetPrototypeOf(_ v: JSObject?) throws -> bool {
        return OrdinarySetPrototypeOf(v)
    }

    public func OrdinarySetPrototypeOf(_ v: JSObject?) -> bool {
        if v === Proto { return true }
        if !Extensible { return false }
        var p = v
        while let q = p {
            if q === self { return false }
            if q is ProxyObject { break }
            p = q.Proto
        }
        Proto = v
        return true
    }

    open func IsExtensibleObject() throws -> bool {
        return Extensible
    }

    open func PreventExtensions() throws -> bool {
        Extensible = false
        return true
    }

    open func GetOwnProperty(_ key: value.PropertyKey) throws -> PropertyDescriptor? {
        let i = find(key)
        if i < 0 { return nil }
        return slots[i].Descriptor
    }

    open func DefineOwnProperty(_ key: value.PropertyKey, _ desc: PropertyDescriptor) throws -> bool {
        return try OrdinaryDefineOwnProperty(key, desc)
    }

    public func OrdinaryDefineOwnProperty(_ key: value.PropertyKey, _ desc: PropertyDescriptor) throws -> bool {
        let current = try GetOwnProperty(key)
        let ext = try IsExtensibleObject()
        return ValidateAndApply(key, ext, desc, current)
    }

    /// ValidateAndApply is ValidateAndApplyPropertyDescriptor (§10.1.6.3)
    /// for this object's own storage.
    public func ValidateAndApply(_ key: value.PropertyKey, _ extensible: bool, _ desc: PropertyDescriptor, _ current: PropertyDescriptor?) -> bool {
        guard let cur = current else {
            if !extensible { return false }
            if desc.IsAccessor {
                var f: uint8 = fAccessor
                if desc.Enumerable ?? false { f |= fEnumerable }
                if desc.Configurable ?? false { f |= fConfigurable }
                var s = Slot(value: .undefined, flags: f)
                if let g = desc.Get, case .object(let go) = g { s.Getter = go }
                if let st = desc.Set, case .object(let so) = st { s.Setter = so }
                store(key, s)
            } else {
                var f: uint8 = 0
                if desc.Writable ?? false { f |= fWritable }
                if desc.Enumerable ?? false { f |= fEnumerable }
                if desc.Configurable ?? false { f |= fConfigurable }
                store(key, Slot(value: desc.Value ?? .undefined, flags: f))
            }
            return true
        }
        if desc.Value == nil && desc.Writable == nil && desc.Get == nil && desc.Set == nil && desc.Enumerable == nil && desc.Configurable == nil {
            return true
        }
        if cur.Configurable == false {
            if desc.Configurable == true { return false }
            if let e = desc.Enumerable, e != cur.Enumerable! { return false }
            if !desc.IsGeneric && desc.IsAccessor != cur.IsAccessor { return false }
            if cur.IsAccessor {
                if let g = desc.Get, !SameValue(g, cur.Get!) { return false }
                if let s = desc.Set, !SameValue(s, cur.Set!) { return false }
            } else if cur.Writable == false {
                if desc.Writable == true { return false }
                if let v = desc.Value, !SameValue(v, cur.Value!) { return false }
            }
        }
        // Apply.
        let i = find(key)
        if i < 0 {
            // A virtual property (array index, string index): the subclass
            // stores it itself.
            return true
        }
        var s = slots[i]
        if cur.IsAccessor && desc.IsData {
            s.Flags = s.Flags & (fEnumerable | fConfigurable)
            s.Getter = nil
            s.Setter = nil
            s.Value = .undefined
        } else if cur.IsData && desc.IsAccessor {
            s.Flags = (s.Flags & (fEnumerable | fConfigurable)) | fAccessor
            s.Value = .undefined
        }
        if let v = desc.Value { s.Value = v }
        if let w = desc.Writable {
            if w { s.Flags |= fWritable } else { s.Flags &= ~fWritable }
        }
        if let g = desc.Get {
            if case .object(let go) = g { s.Getter = go } else { s.Getter = nil }
        }
        if let st = desc.Set {
            if case .object(let so) = st { s.Setter = so } else { s.Setter = nil }
        }
        if let e = desc.Enumerable {
            if e { s.Flags |= fEnumerable } else { s.Flags &= ~fEnumerable }
        }
        if let c = desc.Configurable {
            if c { s.Flags |= fConfigurable } else { s.Flags &= ~fConfigurable }
        }
        slots[i] = s
        return true
    }

    open func HasProperty(_ key: value.PropertyKey) throws -> bool {
        var o: JSObject = self
        while true {
            if o.isOrdinaryLookup {
                if o.find(key) >= 0 { return true }
                guard let p = o.Proto else { return false }
                o = p
                continue
            }
            return try o.HasPropertySlow(key)
        }
    }

    public func HasPropertySlow(_ key: value.PropertyKey) throws -> bool {
        if try GetOwnProperty(key) != nil { return true }
        guard let p = try GetPrototypeOf() else { return false }
        return try p.HasProperty(key)
    }

    /// isOrdinaryLookup says whether GetOwnProperty is the ordinary one,
    /// so lookups can read storage directly.
    open var isOrdinaryLookup: bool { return true }

    open func Get(_ key: value.PropertyKey, _ receiver: Value) throws -> Value {
        var o: JSObject = self
        while true {
            if o.isOrdinaryLookup {
                let i = o.find(key)
                if i >= 0 {
                    let s = o.slots[i]
                    if s.Flags & fAccessor == 0 { return s.Value }
                    guard let g = s.Getter else { return .undefined }
                    return try g.Call(receiver, [])
                }
                guard let p = o.Proto else { return .undefined }
                o = p
                continue
            }
            if o !== self { return try o.Get(key, receiver) }
            return try GetSlow(key, receiver)
        }
    }

    public func GetSlow(_ key: value.PropertyKey, _ receiver: Value) throws -> Value {
        guard let desc = try GetOwnProperty(key) else {
            guard let p = try GetPrototypeOf() else { return .undefined }
            return try p.Get(key, receiver)
        }
        if desc.IsData { return desc.Value ?? .undefined }
        guard let g = desc.Get, case .object(let go) = g else { return .undefined }
        return try go.Call(receiver, [])
    }

    open func Set(_ key: value.PropertyKey, _ v: Value, _ receiver: Value) throws -> bool {
        // Fast path: an own writable data property on the receiver itself.
        if isOrdinaryLookup, case .object(let r) = receiver, r === self {
            let i = find(key)
            if i >= 0 && slots[i].Flags & (fAccessor | fWritable) == fWritable {
                slots[i].Value = v
                return true
            }
        }
        return try OrdinarySet(key, v, receiver)
    }

    /// OrdinarySet is OrdinarySetWithOwnDescriptor (§10.1.9.2).
    public func OrdinarySet(_ key: value.PropertyKey, _ v: Value, _ receiver: Value) throws -> bool {
        var ownDesc = try GetOwnProperty(key)
        if ownDesc == nil {
            if let parent = try GetPrototypeOf() {
                return try parent.Set(key, v, receiver)
            }
            ownDesc = PropertyDescriptor.Data(.undefined)
        }
        let d = ownDesc!
        if d.IsData {
            if d.Writable == false { return false }
            guard case .object(let r) = receiver else { return false }
            if let existing = try r.GetOwnProperty(key) {
                if existing.IsAccessor { return false }
                if existing.Writable == false { return false }
                var vd = PropertyDescriptor()
                vd.Value = v
                return try r.DefineOwnProperty(key, vd)
            }
            return try r.DefineOwnProperty(key, PropertyDescriptor.Data(v))
        }
        guard let s = d.Set, case .object(let so) = s else { return false }
        _ = try so.Call(receiver, [v])
        return true
    }

    open func Delete(_ key: value.PropertyKey) throws -> bool {
        let i = find(key)
        if i < 0 { return true }
        if slots[i].Flags & fConfigurable == 0 { return false }
        remove(key)
        return true
    }

    open func OwnPropertyKeys() throws -> [value.PropertyKey] {
        return OrdinaryOwnPropertyKeys()
    }

    /// OrdinaryOwnPropertyKeys orders keys: integer indices ascending, then
    /// strings and then symbols in the order they were added.
    public func OrdinaryOwnPropertyKeys() -> [value.PropertyKey] {
        var ints: [uint32] = []
        var strs: [value.PropertyKey] = []
        var syms: [value.PropertyKey] = []
        var i = 0
        while i < keys.count {
            if slots[i].Flags & fDeleted == 0 {
                switch keys[i] {
                case .index(let x): ints.append(x)
                case .string: strs.append(keys[i])
                case .symbol(let s): if !s.IsPrivate { syms.append(keys[i]) }
                }
            }
            i += 1
        }
        var out: [value.PropertyKey] = []
        if !ints.isEmpty {
            ints.sort()
            for x in ints { out.append(.index(x)) }
        }
        out.append(contentsOf: strs)
        out.append(contentsOf: syms)
        return out
    }

    // MARK: functions

    open var IsCallable: bool { return false }
    open var IsConstructor: bool { return false }

    /// Call is [[Call]]; only callable objects have it.
    open func Call(_ this: Value, _ args: [Value]) throws -> Value {
        throw ThrowTypeError("object is not a function")
    }

    /// Construct is [[Construct]]; only constructors have it.
    open func Construct(_ args: [Value], _ newTarget: JSObject) throws -> Value {
        throw ThrowTypeError("object is not a constructor")
    }

    // MARK: private elements (§7.3.26–§7.3.32)

    public func PrivateFind(_ name: value.Symbol) -> int {
        return find(.symbol(name))
    }
}

/// OrdinaryObject is a plain object with a given prototype.
public func NewObject(_ proto: JSObject?) -> JSObject {
    return JSObject(proto: proto)
}

/// Key helpers.
public func Key(_ s: string) -> value.PropertyKey {
    return value.PropertyKey.Named(s)
}

public func SymKey(_ s: value.Symbol) -> value.PropertyKey {
    return .symbol(s)
}

let keyLength = value.PropertyKey.Named("length")
let keyPrototype = value.PropertyKey.Named("prototype")
let keyConstructor = value.PropertyKey.Named("constructor")
let keyName = value.PropertyKey.Named("name")
let keyMessage = value.PropertyKey.Named("message")
let keyValue = value.PropertyKey.Named("value")
let keyDone = value.PropertyKey.Named("done")
let keyNext = value.PropertyKey.Named("next")
let keyThen = value.PropertyKey.Named("then")
let keyToString = value.PropertyKey.Named("toString")
let keyValueOf = value.PropertyKey.Named("valueOf")
let keyCallee = value.PropertyKey.Named("callee")
let keyStack = value.PropertyKey.Named("stack")
let keyCause = value.PropertyKey.Named("cause")
let keyReturn = value.PropertyKey.Named("return")
let keyThrow = value.PropertyKey.Named("throw")
let keyGet = value.PropertyKey.Named("get")
let keySet = value.PropertyKey.Named("set")
let keyEnumerable = value.PropertyKey.Named("enumerable")
let keyConfigurable = value.PropertyKey.Named("configurable")
let keyWritable = value.PropertyKey.Named("writable")
let keyLastIndex = value.PropertyKey.Named("lastIndex")
let keyIndex = value.PropertyKey.Named("index")
let keyInput = value.PropertyKey.Named("input")
let keyGroups = value.PropertyKey.Named("groups")
let keyErrors = value.PropertyKey.Named("errors")
