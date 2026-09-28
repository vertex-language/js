package object

import (
    "js/str"
    "js/value"
)

// MARK: errors

/// MakeError creates an error object with a message and a stack trace.
public func MakeError(_ proto: JSObject, _ message: str.JSString) -> JSObject {
    let e = JSObject(proto: proto)
    e.Kind = .error
    if message.Length > 0 {
        e.DefineData(keyMessage, .string(message), writable: true, enumerable: false, configurable: true)
    }
    InstallStack(e)
    return e
}

/// InstallStack gives an error its stack property: its name and message,
/// then the running frames.
public func InstallStack(_ e: JSObject) {
    guard let r = currentRealmStorage else { return }
    var head = "Error"
    if let n = try? e.Get(keyName, .object(e)), case .string(let ns) = n { head = ns.String }
    if let m = try? e.Get(keyMessage, .object(e)), case .string(let ms) = m, ms.Length > 0 {
        head += ": " + ms.String
    }
    var trace = ""
    if let eng = r.Engine { trace = eng.StackTrace() }
    let s = trace.isEmpty ? head : head + "\n" + trace
    e.DefineData(keyStack, .string(str.JSString.From(s)), writable: true, enumerable: false, configurable: true)
}

public func ThrowTypeError(_ msg: string) -> Completion {
    return .thrown(.object(MakeError(CurrentRealm().TypeErrorPrototype, str.JSString.From(msg))))
}

public func ThrowRangeError(_ msg: string) -> Completion {
    return .thrown(.object(MakeError(CurrentRealm().RangeErrorPrototype, str.JSString.From(msg))))
}

public func ThrowReferenceError(_ msg: string) -> Completion {
    return .thrown(.object(MakeError(CurrentRealm().ReferenceErrorPrototype, str.JSString.From(msg))))
}

public func ThrowSyntaxError(_ msg: string) -> Completion {
    return .thrown(.object(MakeError(CurrentRealm().SyntaxErrorPrototype, str.JSString.From(msg))))
}

public func ThrowURIError(_ msg: string) -> Completion {
    return .thrown(.object(MakeError(CurrentRealm().URIErrorPrototype, str.JSString.From(msg))))
}

/// Describe is a short form of a value for error messages, as V8 writes them.
public func Describe(_ v: Value) -> string {
    switch v {
    case .undefined, .empty: return "undefined"
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .number(let d): return value.NumberToString(d)
    case .string(let s): return "\"" + s.String + "\""
    case .symbol(let s): return s.DescriptiveString
    case .bigint(let b): return b.ToString(10)
    case .object(let o):
        if o.IsCallable {
            if let n = o.OwnSlot(keyName), case .string(let s) = n.Value, s.Length > 0 {
                return "function " + s.String
            }
            return "function"
        }
        if o.Kind == .array { return "[object Array]" }
        return "#<" + ClassNameOf(o) + ">"
    }
}

/// ClassNameOf is the constructor name V8 shows in #<Name>.
public func ClassNameOf(_ o: JSObject) -> string {
    var p: JSObject? = o
    while let x = p {
        if let c = x.OwnSlot(keyConstructor), case .object(let co) = c.Value {
            if let n = co.OwnSlot(keyName), case .string(let s) = n.Value, s.Length > 0 {
                return s.String
            }
        }
        p = x.Proto
    }
    return "Object"
}

// MARK: type conversion (§7.1)

public enum Hint {
    case defaultHint
    case number
    case string
}

/// ToPrimitive (§7.1.1).
public func ToPrimitive(_ v: Value, _ hint: Hint = .defaultHint) throws -> Value {
    guard case .object(let o) = v else { return v }
    let exotic = try GetMethod(v, .symbol(value.SymToPrimitive))
    if case .object(let f) = exotic {
        var h = "default"
        if hint == .number { h = "number" } else if hint == .string { h = "string" }
        let r = try f.Call(v, [.string(str.Name(h))])
        if r.IsObject { throw ThrowTypeError("Cannot convert object to primitive value") }
        return r
    }
    return try OrdinaryToPrimitive(o, hint == .string ? .string : .number)
}

/// OrdinaryToPrimitive (§7.1.1.1).
public func OrdinaryToPrimitive(_ o: JSObject, _ hint: Hint) throws -> Value {
    let order: [PropertyKey] = hint == .string ? [keyToString, keyValueOf] : [keyValueOf, keyToString]
    for k in order {
        let m = try o.Get(k, .object(o))
        if case .object(let f) = m, f.IsCallable {
            let r = try f.Call(.object(o), [])
            if !r.IsObject { return r }
        }
    }
    throw ThrowTypeError("Cannot convert object to primitive value")
}

/// ToNumber (§7.1.4).
public func ToNumber(_ v: Value) throws -> float64 {
    switch v {
    case .number(let d): return d
    case .undefined, .empty: return float64.nan
    case .null: return 0
    case .bool(let b): return b ? 1 : 0
    case .string(let s): return value.StringToNumber(s)
    case .symbol: throw ThrowTypeError("Cannot convert a Symbol value to a number")
    case .bigint: throw ThrowTypeError("Cannot convert a BigInt value to a number")
    case .object:
        return try ToNumber(try ToPrimitive(v, .number))
    }
}

/// ToNumeric (§7.1.3): a number or a BigInt.
public func ToNumeric(_ v: Value) throws -> Value {
    switch v {
    case .number, .bigint: return v
    case .object:
        let p = try ToPrimitive(v, .number)
        if case .bigint = p { return p }
        return .number(try ToNumber(p))
    default:
        return .number(try ToNumber(v))
    }
}

/// ToString (§7.1.17).
public func ToString(_ v: Value) throws -> str.JSString {
    switch v {
    case .string(let s): return s
    case .number(let d): return value.NumberToJSString(d)
    case .undefined, .empty: return strUndefined
    case .null: return strNull
    case .bool(let b): return b ? strTrue : strFalse
    case .bigint(let b): return str.JSString.From(b.ToString(10))
    case .symbol: throw ThrowTypeError("Cannot convert a Symbol value to a string")
    case .object:
        return try ToString(try ToPrimitive(v, .string))
    }
}

let strUndefined = str.Name("undefined")
let strNull = str.Name("null")
let strTrue = str.Name("true")
let strFalse = str.Name("false")

/// ToPropertyKey (§7.1.19).
public func ToPropertyKey(_ v: Value) throws -> PropertyKey {
    switch v {
    case .string(let s): return PropertyKey.FromString(s)
    case .number(let d): return PropertyKey.FromNumber(d)
    case .symbol(let s): return .symbol(s)
    default:
        let p = try ToPrimitive(v, .string)
        if case .symbol(let s) = p { return .symbol(s) }
        return PropertyKey.FromString(try ToString(p))
    }
}

/// KeyToValue is a property key as a language value.
public func KeyToValue(_ k: PropertyKey) -> Value {
    switch k {
    case .index(let i): return .string(value.NumberToJSString(float64(i)))
    case .string(let s): return .string(s)
    case .symbol(let s): return .symbol(s)
    }
}

/// ToObject (§7.1.18).
public func ToObject(_ v: Value) throws -> JSObject {
    let r = CurrentRealm()
    switch v {
    case .object(let o): return o
    case .undefined, .null, .empty:
        throw ThrowTypeError("Cannot convert undefined or null to object")
    case .bool:
        let o = JSObject(proto: r.BooleanPrototype)
        o.Kind = .boolean
        o.PrimitiveValue = v
        return o
    case .number:
        let o = JSObject(proto: r.NumberPrototype)
        o.Kind = .number
        o.PrimitiveValue = v
        return o
    case .string(let s):
        return StringObject(s, proto: r.StringPrototype)
    case .symbol:
        let o = JSObject(proto: r.SymbolPrototype)
        o.Kind = .symbol
        o.PrimitiveValue = v
        return o
    case .bigint:
        let o = JSObject(proto: r.BigIntPrototype)
        o.Kind = .bigint
        o.PrimitiveValue = v
        return o
    }
}

/// ToIntegerOrInfinity (§7.1.5).
public func ToIntegerOrInfinity(_ v: Value) throws -> float64 {
    return value.ToIntegerOrInfinity(try ToNumber(v))
}

public func ToInt32(_ v: Value) throws -> int32 {
    if case .number(let d) = v { return value.DoubleToInt32(d) }
    return value.DoubleToInt32(try ToNumber(v))
}

public func ToUint32(_ v: Value) throws -> uint32 {
    return uint32(bitPattern: try ToInt32(v))
}

/// ToLength (§7.1.20).
public func ToLength(_ v: Value) throws -> float64 {
    let len = try ToIntegerOrInfinity(v)
    if len <= 0 { return 0 }
    return len < 9007199254740991 ? len : 9007199254740991
}

/// ToIndex (§7.1.22).
public func ToIndex(_ v: Value) throws -> int {
    if v.IsUndefined { return 0 }
    let i = try ToIntegerOrInfinity(v)
    if i < 0 || i > 9007199254740991 { throw ThrowRangeError("Invalid index") }
    return int(i)
}

/// ToBigInt (§7.1.13).
public func ToBigInt(_ v: Value) throws -> value.BigInt {
    let p = try ToPrimitive(v, .number)
    switch p {
    case .bigint(let b): return b
    case .bool(let b): return b ? value.BigInt.One : value.BigInt.Zero
    case .string(let s):
        let t = value.TrimSpace(s.Units)
        if let b = value.BigInt.Parse(str.JSString(t).String) { return b }
        throw ThrowSyntaxError("Cannot convert \(s.String) to a BigInt")
    case .number(let d):
        throw ThrowTypeError("Cannot convert \(value.NumberToString(d)) to a BigInt")
    case .undefined, .empty: throw ThrowTypeError("Cannot convert undefined to a BigInt")
    case .null: throw ThrowTypeError("Cannot convert null to a BigInt")
    case .symbol: throw ThrowTypeError("Cannot convert a Symbol value to a BigInt")
    case .object: throw ThrowTypeError("Cannot convert object to a BigInt")
    }
}

/// RequireObjectCoercible (§7.2.1).
public func RequireObjectCoercible(_ v: Value) throws {
    if v.IsNullish || v.IsEmpty {
        throw ThrowTypeError("Cannot convert undefined or null to object")
    }
}

// MARK: testing and comparison (§7.2)

/// IsArray (§7.2.2) sees through proxies.
public func IsArray(_ v: Value) throws -> bool {
    guard case .object(let o) = v else { return false }
    if o.Kind == .array { return true }
    if let p = o as? ProxyObject {
        guard let t = p.Target else { throw ThrowTypeError("Cannot perform 'IsArray' on a proxy that has been revoked") }
        return try IsArray(.object(t))
    }
    return false
}

/// IsLooselyEqual (§7.2.14), the == operator.
public func LooseEquals(_ x: Value, _ y: Value) throws -> bool {
    switch (x, y) {
    case (.number(let a), .number(let b)): return a == b
    case (.string(let a), .string(let b)): return a.Equals(b)
    case (.undefined, .undefined), (.null, .null), (.undefined, .null), (.null, .undefined): return true
    case (.bool(let a), .bool(let b)): return a == b
    case (.symbol(let a), .symbol(let b)): return a === b
    case (.bigint(let a), .bigint(let b)): return value.BigInt.Equal(a, b)
    case (.object(let a), .object(let b)): return a === b
    case (.object(let o), .undefined), (.object(let o), .null): return o.IsHTMLDDA
    case (.undefined, .object(let o)), (.null, .object(let o)): return o.IsHTMLDDA
    case (.number(let a), .string(let s)): return a == value.StringToNumber(s)
    case (.string(let s), .number(let b)): return value.StringToNumber(s) == b
    case (.bigint(let a), .string(let s)):
        guard let b = value.BigInt.Parse(str.JSString(value.TrimSpace(s.Units)).String) else { return false }
        return value.BigInt.Equal(a, b)
    case (.string, .bigint): return try LooseEquals(y, x)
    case (.bool(let b), _): return try LooseEquals(.number(b ? 1 : 0), y)
    case (_, .bool(let b)): return try LooseEquals(x, .number(b ? 1 : 0))
    case (.object, .number), (.object, .string), (.object, .bigint), (.object, .symbol):
        return try LooseEquals(try ToPrimitive(x), y)
    case (.number, .object), (.string, .object), (.bigint, .object), (.symbol, .object):
        return try LooseEquals(x, try ToPrimitive(y))
    case (.bigint(let a), .number(let b)): return compareBigNumber(a, b) == 0
    case (.number(let a), .bigint(let b)): return compareBigNumber(b, a) == 0
    default: return false
    }
}

/// compareBigNumber compares a BigInt with a number: -1, 0, 1, or 2 for NaN.
func compareBigNumber(_ a: value.BigInt, _ b: float64) -> int {
    if b.isNaN { return 2 }
    if b.isInfinite { return b > 0 ? -1 : 1 }
    let fl = b.rounded(.down)
    let c = value.BigInt.Compare(a, value.BigInt.FromDouble(fl))
    if c != 0 { return c }
    return fl < b ? -1 : 0
}

/// IsLessThan (§7.2.13): true, false, or nil for undefined (a NaN).
public func LessThan(_ x: Value, _ y: Value, leftFirst: bool) throws -> bool? {
    var px: Value
    var py: Value
    if leftFirst {
        px = try ToPrimitive(x, .number)
        py = try ToPrimitive(y, .number)
    } else {
        py = try ToPrimitive(y, .number)
        px = try ToPrimitive(x, .number)
    }
    if case .string(let a) = px, case .string(let b) = py {
        return a.Compare(b) < 0
    }
    if case .bigint(let a) = px, case .string(let b) = py {
        guard let bb = value.BigInt.Parse(str.JSString(value.TrimSpace(b.Units)).String) else { return nil }
        return value.BigInt.Compare(a, bb) < 0
    }
    if case .string(let a) = px, case .bigint(let b) = py {
        guard let aa = value.BigInt.Parse(str.JSString(value.TrimSpace(a.Units)).String) else { return nil }
        return value.BigInt.Compare(aa, b) < 0
    }
    let nx = try ToNumeric(px)
    let ny = try ToNumeric(py)
    switch (nx, ny) {
    case (.number(let a), .number(let b)):
        if a.isNaN || b.isNaN { return nil }
        return a < b
    case (.bigint(let a), .bigint(let b)):
        return value.BigInt.Compare(a, b) < 0
    case (.bigint(let a), .number(let b)):
        let c = compareBigNumber(a, b)
        if c == 2 { return nil }
        return c < 0
    case (.number(let a), .bigint(let b)):
        let c = compareBigNumber(b, a)
        if c == 2 { return nil }
        return c > 0
    default:
        return nil
    }
}

// MARK: operations on objects (§7.3)

/// GetV (§7.3.3) gets a property of any value, looking primitives up on
/// their prototype.
public func GetV(_ v: Value, _ key: PropertyKey) throws -> Value {
    switch v {
    case .object(let o):
        return try o.Get(key, v)
    case .string(let s):
        if case .index(let i) = key, int(i) < s.Length {
            return .string(str.JSString([s.At(int(i))]))
        }
        if key == keyLength { return .number(float64(s.Length)) }
        return try CurrentRealm().StringPrototype.Get(key, v)
    case .number:
        return try CurrentRealm().NumberPrototype.Get(key, v)
    case .bool:
        return try CurrentRealm().BooleanPrototype.Get(key, v)
    case .symbol:
        return try CurrentRealm().SymbolPrototype.Get(key, v)
    case .bigint:
        return try CurrentRealm().BigIntPrototype.Get(key, v)
    case .undefined, .null, .empty:
        throw ThrowTypeError("Cannot read properties of \(v.IsNull ? "null" : "undefined") (reading '\(KeyDisplay(key))')")
    }
}

/// KeyDisplay is a key as V8 quotes it in messages.
public func KeyDisplay(_ k: PropertyKey) -> string {
    switch k {
    case .index(let i): return "\(i)"
    case .string(let s): return s.String
    case .symbol(let s): return s.DescriptiveString
    }
}

/// Get (§7.3.2).
public func Get(_ o: JSObject, _ key: PropertyKey) throws -> Value {
    return try o.Get(key, .object(o))
}

/// GetMethod (§7.3.11): undefined for null or undefined, else it must be callable.
public func GetMethod(_ v: Value, _ key: PropertyKey) throws -> Value {
    let f = try GetV(v, key)
    if f.IsNullish { return .undefined }
    if !f.IsCallable {
        throw ThrowTypeError("\(Describe(f)) is not a function")
    }
    return f
}

/// SetOrThrow is Set(O, P, V, Throw) (§7.3.4).
public func SetProperty(_ o: JSObject, _ key: PropertyKey, _ v: Value, throwing: bool) throws {
    let ok = try o.Set(key, v, .object(o))
    if !ok && throwing {
        throw ThrowTypeError("Cannot assign to read only property '\(KeyDisplay(key))' of object")
    }
}

/// PutValue for a property reference on any base value, as the
/// interpreter's assignments do it.
public func PutProperty(_ base: Value, _ key: PropertyKey, _ v: Value, strict: bool) throws {
    switch base {
    case .object(let o):
        let ok = try o.Set(key, v, base)
        if !ok && strict {
            throw ThrowTypeError("Cannot assign to read only property '\(KeyDisplay(key))' of \(o.IsCallable ? "function" : "object") '\(DescribeForAssign(o))'")
        }
    case .undefined, .null, .empty:
        throw ThrowTypeError("Cannot set properties of \(base.IsNull ? "null" : "undefined") (setting '\(KeyDisplay(key))')")
    default:
        let proto = try ToObject(base)
        let ok = try proto.Set(key, v, base)
        if !ok && strict {
            throw ThrowTypeError("Cannot create property '\(KeyDisplay(key))' on \(base.TypeOf) '\(try ToString(base).String)'")
        }
    }
}

func DescribeForAssign(_ o: JSObject) -> string {
    if o.Kind == .array { return "[object Array]" }
    if o.IsCallable { return Describe(.object(o)) }
    return "#<" + ClassNameOf(o) + ">"
}

/// CreateDataProperty (§7.3.5).
public func CreateDataProperty(_ o: JSObject, _ key: PropertyKey, _ v: Value) throws -> bool {
    return try o.DefineOwnProperty(key, PropertyDescriptor.Data(v))
}

/// CreateDataPropertyOrThrow (§7.3.7).
public func CreateDataPropertyOrThrow(_ o: JSObject, _ key: PropertyKey, _ v: Value) throws {
    if !(try CreateDataProperty(o, key, v)) {
        throw ThrowTypeError("Cannot define property \(KeyDisplay(key)), object is not extensible")
    }
}

/// DefinePropertyOrThrow (§7.3.8).
public func DefinePropertyOrThrow(_ o: JSObject, _ key: PropertyKey, _ d: PropertyDescriptor) throws {
    if !(try o.DefineOwnProperty(key, d)) {
        throw ThrowTypeError("Cannot redefine property: \(KeyDisplay(key))")
    }
}

/// DeletePropertyOrThrow (§7.3.9).
public func DeletePropertyOrThrow(_ o: JSObject, _ key: PropertyKey) throws {
    if !(try o.Delete(key)) {
        throw ThrowTypeError("Cannot delete property '\(KeyDisplay(key))' of \(DescribeForAssign(o))")
    }
}

/// HasOwnProperty (§7.3.13).
public func HasOwnProperty(_ o: JSObject, _ key: PropertyKey) throws -> bool {
    if o.isOrdinaryLookup { return o.find(key) >= 0 }
    return try o.GetOwnProperty(key) != nil
}

/// Call (§7.3.14).
public func Call(_ f: Value, _ this: Value, _ args: [Value]) throws -> Value {
    guard case .object(let o) = f, o.IsCallable else {
        throw ThrowTypeError("\(Describe(f)) is not a function")
    }
    return try o.Call(this, args)
}

/// Construct (§7.3.15).
public func Construct(_ f: JSObject, _ args: [Value], _ newTarget: JSObject? = nil) throws -> Value {
    return try f.Construct(args, newTarget ?? f)
}

/// Invoke (§7.3.21): call a method by name.
public func Invoke(_ v: Value, _ key: PropertyKey, _ args: [Value]) throws -> Value {
    let f = try GetV(v, key)
    return try Call(f, v, args)
}

/// SetIntegrityLevel (§7.3.16): sealed or frozen.
public func SetIntegrityLevel(_ o: JSObject, frozen: bool) throws -> bool {
    if !(try o.PreventExtensions()) { return false }
    let keys = try o.OwnPropertyKeys()
    for k in keys {
        var d = PropertyDescriptor()
        d.Configurable = false
        if frozen {
            if let cur = try o.GetOwnProperty(k), cur.IsData {
                d.Writable = false
            }
        }
        try DefinePropertyOrThrow(o, k, d)
    }
    return true
}

/// TestIntegrityLevel (§7.3.17).
public func TestIntegrityLevel(_ o: JSObject, frozen: bool) throws -> bool {
    if try o.IsExtensibleObject() { return false }
    for k in try o.OwnPropertyKeys() {
        if let d = try o.GetOwnProperty(k) {
            if d.Configurable == true { return false }
            if frozen && d.IsData && d.Writable == true { return false }
        }
    }
    return true
}

/// LengthOfArrayLike (§7.3.18).
public func LengthOfArrayLike(_ o: JSObject) throws -> int {
    if let a = o as? ArrayObject { return int(a.Length) }
    return int(try ToLength(try o.Get(keyLength, .object(o))))
}

/// CreateListFromArrayLike (§7.3.19).
public func CreateListFromArrayLike(_ v: Value) throws -> [Value] {
    guard case .object(let o) = v else {
        throw ThrowTypeError("CreateListFromArrayLike called on non-object")
    }
    if let a = o as? ArrayObject, a.IsDenseSimple {
        var out = a.Dense
        var i = 0
        while i < out.count {
            if out[i].IsEmpty { out[i] = try o.Get(.index(uint32(i)), v) }
            i += 1
        }
        return out
    }
    let n = try LengthOfArrayLike(o)
    var out: [Value] = []
    var i = 0
    while i < n {
        out.append(try o.Get(.index(uint32(i)), v))
        i += 1
    }
    return out
}

/// OrdinaryHasInstance (§7.3.22).
public func OrdinaryHasInstance(_ c: Value, _ o: Value) throws -> bool {
    guard case .object(let cf) = c, cf.IsCallable else { return false }
    if let b = cf as? BoundFunction {
        return try InstanceOf(o, .object(b.Target))
    }
    guard case .object(var obj) = o else { return false }
    let p = try cf.Get(keyPrototype, c)
    guard case .object(let proto) = p else {
        throw ThrowTypeError("Function has non-object prototype '\(Describe(p))' in instanceof check")
    }
    while true {
        guard let next = try obj.GetPrototypeOf() else { return false }
        if next === proto { return true }
        obj = next
    }
}

/// InstanceofOperator (§13.10.2).
public func InstanceOf(_ v: Value, _ target: Value) throws -> bool {
    guard case .object = target else {
        throw ThrowTypeError("Right-hand side of 'instanceof' is not an object")
    }
    let h = try GetMethod(target, .symbol(value.SymHasInstance))
    if !h.IsUndefined {
        return try Call(h, target, [v]).Truthy
    }
    if !target.IsCallable {
        throw ThrowTypeError("Right-hand side of 'instanceof' is not callable")
    }
    return try OrdinaryHasInstance(target, v)
}

/// SpeciesConstructor (§7.3.23).
public func SpeciesConstructor(_ o: JSObject, _ def: JSObject) throws -> JSObject {
    let c = try o.Get(keyConstructor, .object(o))
    if c.IsUndefined { return def }
    guard case .object(let co) = c else {
        throw ThrowTypeError("object.constructor is not an object")
    }
    let s = try co.Get(.symbol(value.SymSpecies), c)
    if s.IsNullish { return def }
    if case .object(let so) = s, so.IsConstructor { return so }
    throw ThrowTypeError("object.constructor[Symbol.species] is not a constructor")
}

/// GetPrototypeFromConstructor (§10.1.14).
public func GetPrototypeFromConstructor(_ ctor: JSObject, _ fallback: JSObject) throws -> JSObject {
    let p = try ctor.Get(keyPrototype, .object(ctor))
    if case .object(let po) = p { return po }
    // The fallback comes from the constructor's realm.
    if let f = ctor as? JSFunction {
        return realmIntrinsicLike(fallback, f.Realm)
    }
    return fallback
}

func realmIntrinsicLike(_ o: JSObject, _ r: Realm) -> JSObject {
    return o
}

/// OrdinaryCreateFromConstructor (§10.1.13).
public func OrdinaryCreateFromConstructor(_ ctor: JSObject?, _ fallback: JSObject) throws -> JSObject {
    guard let c = ctor else { return JSObject(proto: fallback) }
    return JSObject(proto: try GetPrototypeFromConstructor(c, fallback))
}

/// EnumerableOwnProperties (§7.3.24): keys, values or entries.
public enum EnumKind {
    case keys
    case values
    case entries
}

public func EnumerableOwnProperties(_ o: JSObject, _ kind: EnumKind) throws -> [Value] {
    let keys = try o.OwnPropertyKeys()
    var out: [Value] = []
    let r = CurrentRealm()
    for k in keys {
        if k.IsSymbol { continue }
        guard let d = try o.GetOwnProperty(k), d.Enumerable == true else { continue }
        let kv = KeyToValue(k)
        switch kind {
        case .keys:
            out.append(kv)
        case .values:
            out.append(try o.Get(k, .object(o)))
        case .entries:
            let v = try o.Get(k, .object(o))
            out.append(.object(CreateArrayFromList(r, [kv, v])))
        }
    }
    return out
}

/// CopyDataProperties (§7.3.25).
public func CopyDataProperties(_ target: JSObject, _ source: Value, excluded: [PropertyKey]) throws {
    if source.IsNullish { return }
    let from = try ToObject(source)
    for k in try from.OwnPropertyKeys() {
        var skip = false
        for e in excluded where e == k { skip = true; break }
        if skip { continue }
        if let d = try from.GetOwnProperty(k), d.Enumerable == true {
            let v = try from.Get(k, .object(from))
            _ = try CreateDataProperty(target, k, v)
        }
    }
}

/// FromPropertyDescriptor (§6.2.6.4).
public func FromPropertyDescriptor(_ d: PropertyDescriptor?) -> Value {
    guard let desc = d else { return .undefined }
    let o = JSObject(proto: CurrentRealm().ObjectPrototype)
    if let v = desc.Value { o.DefineData(keyValue, v) }
    if let w = desc.Writable { o.DefineData(keyWritable, .bool(w)) }
    if let g = desc.Get { o.DefineData(keyGet, g) }
    if let s = desc.Set { o.DefineData(keySet, s) }
    if let e = desc.Enumerable { o.DefineData(keyEnumerable, .bool(e)) }
    if let c = desc.Configurable { o.DefineData(keyConfigurable, .bool(c)) }
    return .object(o)
}

/// ToPropertyDescriptor (§6.2.6.5).
public func ToPropertyDescriptor(_ v: Value) throws -> PropertyDescriptor {
    guard case .object(let o) = v else {
        throw ThrowTypeError("Property description must be an object: \(Describe(v))")
    }
    var d = PropertyDescriptor()
    if try o.HasProperty(keyEnumerable) { d.Enumerable = try o.Get(keyEnumerable, v).Truthy }
    if try o.HasProperty(keyConfigurable) { d.Configurable = try o.Get(keyConfigurable, v).Truthy }
    if try o.HasProperty(keyValue) { d.Value = try o.Get(keyValue, v) }
    if try o.HasProperty(keyWritable) { d.Writable = try o.Get(keyWritable, v).Truthy }
    if try o.HasProperty(keyGet) {
        let g = try o.Get(keyGet, v)
        if !g.IsUndefined && !g.IsCallable { throw ThrowTypeError("Getter must be a function: \(Describe(g))") }
        d.Get = g
    }
    if try o.HasProperty(keySet) {
        let s = try o.Get(keySet, v)
        if !s.IsUndefined && !s.IsCallable { throw ThrowTypeError("Setter must be a function: \(Describe(s))") }
        d.Set = s
    }
    if (d.Get != nil || d.Set != nil) && (d.Value != nil || d.Writable != nil) {
        throw ThrowTypeError("Invalid property descriptor. Cannot both specify accessors and a value or writable attribute")
    }
    return d
}

/// CompletePropertyDescriptor (§6.2.6.6).
public func CompletePropertyDescriptor(_ d: PropertyDescriptor) -> PropertyDescriptor {
    var r = d
    if r.IsGeneric || r.IsData {
        if r.Value == nil { r.Value = .undefined }
        if r.Writable == nil { r.Writable = false }
    } else {
        if r.Get == nil { r.Get = .undefined }
        if r.Set == nil { r.Set = .undefined }
    }
    if r.Enumerable == nil { r.Enumerable = false }
    if r.Configurable == nil { r.Configurable = false }
    return r
}

// MARK: arrays

/// CreateArrayFromList (§7.3.18).
public func CreateArrayFromList(_ r: Realm, _ list: [Value]) -> ArrayObject {
    let a = ArrayObject(proto: r.ArrayPrototype)
    a.Dense = list
    a.Length = uint32(list.count)
    return a
}

/// ArrayCreate (§10.4.2.2).
public func ArrayCreate(_ length: float64, proto: JSObject? = nil) throws -> ArrayObject {
    if length > 4294967295 { throw ThrowRangeError("Invalid array length") }
    let a = ArrayObject(proto: proto ?? CurrentRealm().ArrayPrototype)
    a.Length = uint32(length)
    return a
}

/// ArraySpeciesCreate (§10.4.2.3).
public func ArraySpeciesCreate(_ original: JSObject, _ length: float64) throws -> JSObject {
    if !(try IsArray(.object(original))) {
        return try ArrayCreate(length)
    }
    var c = try original.Get(keyConstructor, .object(original))
    if case .object(let co) = c, co.IsConstructor {
        if let f = co as? JSFunction, f.Realm !== CurrentRealm() {
            if let ac = f.Realm.ArrayConstructor, co === ac { c = .undefined }
        }
    }
    if case .object(let co) = c {
        c = try co.Get(.symbol(value.SymSpecies), c)
        if c.IsNull { c = .undefined }
    }
    if c.IsUndefined { return try ArrayCreate(length) }
    guard case .object(let ctor) = c, ctor.IsConstructor else {
        throw ThrowTypeError("object.constructor[Symbol.species] is not a constructor")
    }
    let r = try ctor.Construct([.number(length)], ctor)
    guard case .object(let ro) = r else { throw ThrowTypeError("species constructor did not return an object") }
    return ro
}

// MARK: operators

/// Arithmetic is the numeric operators of §6.1.6 and §13.15.3's
/// ApplyStringOrNumericBinaryOperator (without +'s string case).
public enum ArithOp {
    case add
    case sub
    case mul
    case div
    case mod
    case exp
    case shl
    case sar
    case shr
    case and
    case or
    case xor
}

/// Add is the + operator.
public func Add(_ x: Value, _ y: Value) throws -> Value {
    if case .number(let a) = x, case .number(let b) = y { return .number(a + b) }
    if case .string(let a) = x, case .string(let b) = y { return .string(a.Concat(b)) }
    let px = try ToPrimitive(x)
    let py = try ToPrimitive(y)
    if px.IsString || py.IsString {
        let sx = try ToString(px)
        let sy = try ToString(py)
        return .string(sx.Concat(sy))
    }
    return try Arithmetic(.add, px, py)
}

/// Arithmetic applies a numeric operator after ToNumeric.
public func Arithmetic(_ op: ArithOp, _ x: Value, _ y: Value) throws -> Value {
    let nx = try ToNumeric(x)
    let ny = try ToNumeric(y)
    switch (nx, ny) {
    case (.number(let a), .number(let b)):
        return .number(NumberOp(op, a, b))
    case (.bigint(let a), .bigint(let b)):
        return .bigint(try BigIntOp(op, a, b))
    default:
        throw ThrowTypeError("Cannot mix BigInt and other types, use explicit conversions")
    }
}

public func NumberOp(_ op: ArithOp, _ a: float64, _ b: float64) -> float64 {
    switch op {
    case .add: return a + b
    case .sub: return a - b
    case .mul: return a * b
    case .div: return a / b
    case .mod: return NumberMod(a, b)
    case .exp: return NumberPow(a, b)
    case .shl:
        let l = value.DoubleToInt32(a)
        let r = value.DoubleToUint32(b) & 31
        return float64(l << int32(r))
    case .sar:
        let l = value.DoubleToInt32(a)
        let r = value.DoubleToUint32(b) & 31
        return float64(l >> int32(r))
    case .shr:
        let l = value.DoubleToUint32(a)
        let r = value.DoubleToUint32(b) & 31
        return float64(int64(l >> r))
    case .and: return float64(value.DoubleToInt32(a) & value.DoubleToInt32(b))
    case .or: return float64(value.DoubleToInt32(a) | value.DoubleToInt32(b))
    case .xor: return float64(value.DoubleToInt32(a) ^ value.DoubleToInt32(b))
    }
}

/// NumberMod is the % operator: the result takes the dividend's sign.
public func NumberMod(_ a: float64, _ b: float64) -> float64 {
    if a.isNaN || b.isNaN || a.isInfinite || b == 0 { return float64.nan }
    if b.isInfinite { return a }
    if a == 0 { return a }
    let r = a.truncatingRemainder(dividingBy: b)
    if r == 0 && a < 0 { return -0.0 }
    return r
}

/// NumberPow is Number::exponentiate (§6.1.6.1.3).
public func NumberPow(_ base: float64, _ e: float64) -> float64 {
    if e.isNaN { return float64.nan }
    if e == 0 { return 1 }
    if base.isNaN { return float64.nan }
    let ab = base < 0 ? -base : base
    if e.isInfinite {
        if ab == 1 { return float64.nan }
        if ab > 1 { return e > 0 ? float64.infinity : 0 }
        return e > 0 ? 0 : float64.infinity
    }
    if e == e.rounded(.towardZero) && (e < 0 ? -e : e) < 9007199254740992 {
        // Integer exponent: repeated squaring, as V8 does for small ones.
        var n = e < 0 ? -e : e
        var result: float64 = 1
        var b = base
        while n > 0 {
            let half = (n / 2).rounded(.down)
            if n - half * 2 == 1 { result *= b }
            b *= b
            n = half
        }
        return e < 0 ? 1 / result : result
    }
    return value.Pow(base, e)
}

public func BigIntOp(_ op: ArithOp, _ a: value.BigInt, _ b: value.BigInt) throws -> value.BigInt {
    switch op {
    case .add: return value.BigInt.Add(a, b)
    case .sub: return value.BigInt.Sub(a, b)
    case .mul: return value.BigInt.Mul(a, b)
    case .div:
        if b.IsZero { throw ThrowRangeError("Division by zero") }
        return value.BigInt.Div(a, b)
    case .mod:
        if b.IsZero { throw ThrowRangeError("Division by zero") }
        return value.BigInt.Rem(a, b)
    case .exp:
        if b.Negative { throw ThrowRangeError("Exponent must be non-negative") }
        return value.BigInt.Pow(a, b)
    case .shl:
        return value.BigInt.ShiftLeft(a, int(b.ToInt64()))
    case .sar:
        return value.BigInt.ShiftLeft(a, -int(b.ToInt64()))
    case .shr:
        throw ThrowTypeError("BigInts have no unsigned right shift, use >> instead")
    case .and: return value.BigInt.BitOp(a, b, 0)
    case .or: return value.BigInt.BitOp(a, b, 1)
    case .xor: return value.BigInt.BitOp(a, b, 2)
    }
}

/// TypeOfValue is the typeof operator as a string value.
public func TypeOfValue(_ v: Value) -> Value {
    return .string(str.Name(v.TypeOf))
}
