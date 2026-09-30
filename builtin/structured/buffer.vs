package structured

import (
    "js/builtin/indexed"
    "js/object"
    "js/str"
    "js/value"
)

// Binary data (ECMA-262 §25.1-§25.4, §23.2): ArrayBuffer (resizable, and
// transferable), SharedArrayBuffer, DataView, the typed arrays -- integer-
// indexed exotic objects over a buffer, length-tracking when made over a
// resizable one without a length -- and Atomics. Elements are stored in
// the platform's order, little-endian; a DataView picks per access.


// MARK: buffers

/// ArrayBufferObject is an ArrayBuffer or a SharedArrayBuffer.
public final class ArrayBufferObject: object.JSObject {
    public var Data: [uint8] = []
    public var Detached: bool = false
    /// MaxByteLength is a resizable (or growable) buffer's limit; -1 for a
    /// fixed-length one.
    public var MaxByteLength: int = -1
    public var Shared: bool = false

    public init(proto: object.JSObject?, length: int, shared: bool) {
        super.init(proto: proto)
        Data = [uint8](repeating: 0, count: length)
        Shared = shared
        Kind = shared ? .sharedArrayBuffer : .arrayBuffer
    }

    public var ByteLength: int { return Detached ? 0 : Data.count }
    public var IsFixedLength: bool { return MaxByteLength < 0 }
}

/// maxAllocation bounds a buffer's size ("Array buffer allocation failed").
let maxAllocation = 1 << 31

func thisBuffer(_ v: Value, shared: bool, _ method: string) throws -> ArrayBufferObject {
    guard case .object(let o) = v, let b = o as? ArrayBufferObject, b.Shared == shared else {
        let name = shared ? "SharedArrayBuffer" : "ArrayBuffer"
        throw object.ThrowTypeError("Method \(name).prototype.\(method) called on incompatible receiver \(object.Describe(v))")
    }
    return b
}

/// maxByteLengthOption is GetArrayBufferMaxByteLengthOption (§25.1.3.7): -1 when none.
func maxByteLengthOption(_ options: Value) throws -> int {
    guard case .object(let o) = options else { return -1 }
    let m = try o.Get(object.Key("maxByteLength"), options)
    if m.IsUndefined { return -1 }
    return try object.ToIndex(m)
}

func allocateBuffer(_ r: object.Realm, _ newTarget: object.JSObject, _ length: int, max: int, shared: bool) throws -> ArrayBufferObject {
    if max >= 0 && length > max {
        throw object.ThrowRangeError("Invalid array buffer max length")
    }
    let fallback = r.Intrinsics[shared ? "SharedArrayBufferPrototype" : "ArrayBufferPrototype"]!
    let proto = try object.GetPrototypeFromConstructor(newTarget, fallback)
    if length > maxAllocation || max > maxAllocation {
        throw object.ThrowRangeError("Array buffer allocation failed")
    }
    let b = ArrayBufferObject(proto: proto, length: length, shared: shared)
    b.MaxByteLength = max
    return b
}

func newBuffer(_ r: object.Realm, _ length: int) throws -> ArrayBufferObject {
    if length > maxAllocation { throw object.ThrowRangeError("Array buffer allocation failed") }
    return ArrayBufferObject(proto: r.Intrinsics["ArrayBufferPrototype"]!, length: length, shared: false)
}

func clampRelative(_ v: Value, _ len: int, _ dflt: int) throws -> int {
    if v.IsUndefined { return dflt }
    let rel = try object.ToIntegerOrInfinity(v)
    if rel < 0 {
        let x = float64(len) + rel
        return x < 0 ? 0 : int(x)
    }
    return rel > float64(len) ? len : int(rel)
}

func installArrayBuffer(_ r: object.Realm) {
    let abp = object.JSObject(proto: r.ObjectPrototype)
    r.Intrinsics["ArrayBufferPrototype"] = abp
    var ctorRef: object.JSObject? = nil
    let ctor = r.Constructor("ArrayBuffer", 1, prototype: abp) { _, args, nt in
        guard let n = nt else { throw object.ThrowTypeError("Constructor ArrayBuffer requires 'new'") }
        let length = try object.ToIndex(object.Arg(args, 0))
        let max = try maxByteLengthOption(object.Arg(args, 1))
        return .object(try allocateBuffer(r, n, length, max: max, shared: false))
    }
    ctorRef = ctor
    r.Intrinsics["ArrayBuffer"] = ctor
    r.Getter(ctor, .symbol(value.SymSpecies)) { thisV, _, _ in return thisV }
    r.Method(ctor, "isView", 1) { _, args, _ in
        if case .object(let o) = object.Arg(args, 0), o is TypedArrayObject || o is DataViewObject { return .bool(true) }
        return .bool(false)
    }
    r.Getter(abp, object.Key("byteLength")) { thisV, _, _ in
        return .number(float64(try thisBuffer(thisV, shared: false, "byteLength").ByteLength))
    }
    r.Getter(abp, object.Key("maxByteLength")) { thisV, _, _ in
        let b = try thisBuffer(thisV, shared: false, "maxByteLength")
        if b.Detached { return .number(0) }
        return .number(float64(b.IsFixedLength ? b.ByteLength : b.MaxByteLength))
    }
    r.Getter(abp, object.Key("resizable")) { thisV, _, _ in
        return .bool(!(try thisBuffer(thisV, shared: false, "resizable")).IsFixedLength)
    }
    r.Getter(abp, object.Key("detached")) { thisV, _, _ in
        return .bool(try thisBuffer(thisV, shared: false, "detached").Detached)
    }
    r.Method(abp, "resize", 1) { thisV, args, _ in
        let b = try thisBuffer(thisV, shared: false, "resize")
        if b.IsFixedLength { throw object.ThrowTypeError("Method ArrayBuffer.prototype.resize called on incompatible receiver \(object.Describe(thisV))") }
        let n = try object.ToIndex(object.Arg(args, 0))
        if b.Detached { throw object.ThrowTypeError("Cannot perform ArrayBuffer.prototype.resize on a detached ArrayBuffer") }
        if n > b.MaxByteLength { throw object.ThrowRangeError("ArrayBuffer.prototype.resize: Invalid length parameter") }
        resizeData(&b.Data, n)
        return .undefined
    }
    r.Method(abp, "slice", 2) { thisV, args, _ in
        let b = try thisBuffer(thisV, shared: false, "slice")
        if b.Detached { throw object.ThrowTypeError("Cannot perform ArrayBuffer.prototype.slice on a detached ArrayBuffer") }
        let len = b.ByteLength
        let first = try clampRelative(object.Arg(args, 0), len, 0)
        let fin = try clampRelative(object.Arg(args, 1), len, len)
        let newLen = max(fin - first, 0)
        let c = try object.SpeciesConstructor(b, ctorRef!)
        guard case .object(let no) = try object.Construct(c, [.number(float64(newLen))]), let nb = no as? ArrayBufferObject, !nb.Shared else {
            throw object.ThrowTypeError("ArrayBuffer subclass returned this from species constructor")
        }
        if nb.Detached { throw object.ThrowTypeError("Cannot perform ArrayBuffer.prototype.slice on a detached ArrayBuffer") }
        if nb === b { throw object.ThrowTypeError("ArrayBuffer subclass returned this from species constructor") }
        if nb.ByteLength < newLen { throw object.ThrowTypeError("Species constructor returned a too-short ArrayBuffer") }
        if b.Detached { throw object.ThrowTypeError("Cannot perform ArrayBuffer.prototype.slice on a detached ArrayBuffer") }
        let cur = b.ByteLength
        var i = 0
        while i < newLen && first + i < cur {
            nb.Data[i] = b.Data[first + i]
            i += 1
        }
        return .object(nb)
    }
    func transfer(_ thisV: Value, _ args: [Value], fixed: bool, _ name: string) throws -> Value {
        let b = try thisBuffer(thisV, shared: false, name)
        let newLenV = object.Arg(args, 0)
        let newLen = newLenV.IsUndefined ? b.ByteLength : try object.ToIndex(newLenV)
        if b.Detached { throw object.ThrowTypeError("Cannot perform ArrayBuffer.prototype.\(name) on a detached ArrayBuffer") }
        let keepMax = !fixed && !b.IsFixedLength
        if keepMax && newLen > b.MaxByteLength { throw object.ThrowRangeError("ArrayBuffer.prototype.\(name): Invalid length parameter") }
        let nb = try newBuffer(r, 0)
        var data = b.Data
        resizeData(&data, newLen)
        nb.Data = data
        nb.MaxByteLength = keepMax ? b.MaxByteLength : -1
        b.Data = []
        b.Detached = true
        return .object(nb)
    }
    r.Method(abp, "transfer", 0) { thisV, args, _ in
        return try transfer(thisV, args, fixed: false, "transfer")
    }
    r.Method(abp, "transferToFixedLength", 0) { thisV, args, _ in
        return try transfer(thisV, args, fixed: true, "transferToFixedLength")
    }
    abp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("ArrayBuffer")), writable: false, enumerable: false, configurable: true)

    // SharedArrayBuffer (§25.2).
    let sabp = object.JSObject(proto: r.ObjectPrototype)
    r.Intrinsics["SharedArrayBufferPrototype"] = sabp
    var sctorRef: object.JSObject? = nil
    let sctor = r.Constructor("SharedArrayBuffer", 1, prototype: sabp) { _, args, nt in
        guard let n = nt else { throw object.ThrowTypeError("Constructor SharedArrayBuffer requires 'new'") }
        let length = try object.ToIndex(object.Arg(args, 0))
        let max = try maxByteLengthOption(object.Arg(args, 1))
        return .object(try allocateBuffer(r, n, length, max: max, shared: true))
    }
    sctorRef = sctor
    r.Getter(sctor, .symbol(value.SymSpecies)) { thisV, _, _ in return thisV }
    r.Getter(sabp, object.Key("byteLength")) { thisV, _, _ in
        return .number(float64(try thisBuffer(thisV, shared: true, "byteLength").ByteLength))
    }
    r.Getter(sabp, object.Key("growable")) { thisV, _, _ in
        return .bool(!(try thisBuffer(thisV, shared: true, "growable")).IsFixedLength)
    }
    r.Getter(sabp, object.Key("maxByteLength")) { thisV, _, _ in
        let b = try thisBuffer(thisV, shared: true, "maxByteLength")
        return .number(float64(b.IsFixedLength ? b.ByteLength : b.MaxByteLength))
    }
    r.Method(sabp, "grow", 1) { thisV, args, _ in
        let b = try thisBuffer(thisV, shared: true, "grow")
        if b.IsFixedLength { throw object.ThrowTypeError("Method SharedArrayBuffer.prototype.grow called on incompatible receiver \(object.Describe(thisV))") }
        let n = try object.ToIndex(object.Arg(args, 0))
        if n > b.MaxByteLength || n < b.ByteLength { throw object.ThrowRangeError("SharedArrayBuffer.prototype.grow: Invalid length parameter") }
        resizeData(&b.Data, n)
        return .undefined
    }
    r.Method(sabp, "slice", 2) { thisV, args, _ in
        let b = try thisBuffer(thisV, shared: true, "slice")
        let len = b.ByteLength
        let first = try clampRelative(object.Arg(args, 0), len, 0)
        let fin = try clampRelative(object.Arg(args, 1), len, len)
        let newLen = max(fin - first, 0)
        let c = try object.SpeciesConstructor(b, sctorRef!)
        guard case .object(let no) = try object.Construct(c, [.number(float64(newLen))]), let nb = no as? ArrayBufferObject, nb.Shared, nb !== b else {
            throw object.ThrowTypeError("SharedArrayBuffer subclass returned this from species constructor")
        }
        if nb.ByteLength < newLen { throw object.ThrowTypeError("Species constructor returned a too-short SharedArrayBuffer") }
        var i = 0
        while i < newLen {
            nb.Data[i] = b.Data[first + i]
            i += 1
        }
        return .object(nb)
    }
    sabp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("SharedArrayBuffer")), writable: false, enumerable: false, configurable: true)
}

func resizeData(_ d: inout [uint8], _ n: int) {
    if n < d.count {
        d = Array(d[0..<n])
    } else {
        while d.count < n { d.append(0) }
    }
}

// MARK: element types

/// ElementType is a typed array's element type (Table 71).
public enum ElementType: Equatable {
    case int8
    case uint8
    case uint8Clamped
    case int16
    case uint16
    case int32
    case uint32
    case float16
    case float32
    case float64
    case bigInt64
    case bigUint64

    public var Size: int {
        switch self {
        case .int8, .uint8, .uint8Clamped: return 1
        case .int16, .uint16, .float16: return 2
        case .int32, .uint32, .float32: return 4
        case .float64, .bigInt64, .bigUint64: return 8
        }
    }

    public var IsBigInt: bool { return self == .bigInt64 || self == .bigUint64 }

    public var Name: string {
        switch self {
        case .int8: return "Int8Array"
        case .uint8: return "Uint8Array"
        case .uint8Clamped: return "Uint8ClampedArray"
        case .int16: return "Int16Array"
        case .uint16: return "Uint16Array"
        case .int32: return "Int32Array"
        case .uint32: return "Uint32Array"
        case .float16: return "Float16Array"
        case .float32: return "Float32Array"
        case .float64: return "Float64Array"
        case .bigInt64: return "BigInt64Array"
        case .bigUint64: return "BigUint64Array"
        }
    }
}

let allElementTypes: [ElementType] = [.int8, .uint8, .uint8Clamped, .int16, .uint16, .int32, .uint32, .float16, .float32, .float64, .bigInt64, .bigUint64]

/// toElementValue converts v for storage: ToBigInt for BigInt types,
/// ToNumber otherwise.
func toElementValue(_ t: ElementType, _ v: Value) throws -> Value {
    if t.IsBigInt { return .bigint(try object.ToBigInt(v)) }
    if case .number = v { return v }
    return .number(try object.ToNumber(v))
}

/// modular is ToUint32-style wrapping of a number (NaN and infinities to 0).
func modular(_ d: float64) -> uint64 {
    if d.isNaN || d.isInfinite { return 0 }
    let t = d.rounded(.towardZero)
    var m = t.truncatingRemainder(dividingBy: 4294967296.0)
    if m < 0 { m += 4294967296.0 }
    return uint64(m)
}

func clampUint8(_ d: float64) -> uint64 {
    if d.isNaN || d <= 0 { return 0 }
    if d >= 255 { return 255 }
    let f = d.rounded(.down)
    if f + 0.5 < d { return uint64(f + 1) }
    if d < f + 0.5 { return uint64(f) }
    let fi = uint64(f)
    return fi % 2 == 0 ? fi : fi + 1
}

/// elementBits is NumericToRawBytes as an integer of the element's width.
func elementBits(_ t: ElementType, _ v: Value) -> uint64 {
    switch t {
    case .bigInt64, .bigUint64:
        if case .bigint(let b) = v { return b.ToUInt64() }
        return 0
    default:
        break
    }
    var d: float64 = 0
    if case .number(let n) = v { d = n }
    switch t {
    case .int8, .uint8: return modular(d) & 0xFF
    case .uint8Clamped: return clampUint8(d)
    case .int16, .uint16: return modular(d) & 0xFFFF
    case .int32, .uint32: return modular(d) & 0xFFFFFFFF
    case .float16: return uint64(float16(d).bitPattern)
    case .float32: return uint64(float32(d).bitPattern)
    case .float64: return d.bitPattern
    default: return 0
    }
}

/// bitsValue is RawBytesToNumeric.
func bitsValue(_ t: ElementType, _ bits: uint64) -> Value {
    switch t {
    case .int8:
        let v = int(bits & 0xFF)
        return .number(float64(v >= 128 ? v - 256 : v))
    case .uint8, .uint8Clamped:
        return .number(float64(bits & 0xFF))
    case .int16:
        let v = int(bits & 0xFFFF)
        return .number(float64(v >= 32768 ? v - 65536 : v))
    case .uint16:
        return .number(float64(bits & 0xFFFF))
    case .int32:
        let v = int64(bits & 0xFFFFFFFF)
        return .number(float64(v >= 2147483648 ? v - 4294967296 : v))
    case .uint32:
        return .number(float64(bits & 0xFFFFFFFF))
    case .float16:
        return .number(float64(float16(bitPattern: uint16(bits & 0xFFFF))))
    case .float32:
        return .number(float64(float32(bitPattern: uint32(bits & 0xFFFFFFFF))))
    case .float64:
        return .number(float64(bitPattern: bits))
    case .bigInt64:
        return .bigint(value.BigInt.FromInt(int64(bitPattern: bits)))
    case .bigUint64:
        return .bigint(value.BigInt.AsUintN(64, value.BigInt.FromInt(int64(bitPattern: bits))))
    }
}

func readBits(_ data: [uint8], _ off: int, _ size: int, little: bool) -> uint64 {
    var v: uint64 = 0
    var i = 0
    while i < size {
        let byte = uint64(data[off + (little ? i : size - 1 - i)])
        v |= byte << uint64(8 * i)
        i += 1
    }
    return v
}

func writeBits(_ data: inout [uint8], _ off: int, _ size: int, _ bits: uint64, little: bool) {
    var i = 0
    while i < size {
        data[off + (little ? i : size - 1 - i)] = uint8((bits >> uint64(8 * i)) & 0xFF)
        i += 1
    }
}

// MARK: typed arrays

/// TypedArrayObject is a typed array: an integer-indexed exotic object
/// (§10.4.5) viewing Buffer from ByteOffset.
public final class TypedArrayObject: object.JSObject {
    public var Buffer: ArrayBufferObject
    public var ByteOffset: int = 0
    /// FixedLength is the length given when made, or -1 for a view that
    /// tracks a resizable buffer's length.
    public var FixedLength: int = -1
    public let Type: ElementType

    public init(proto: object.JSObject?, type: ElementType, buffer: ArrayBufferObject) {
        self.Type = type
        self.Buffer = buffer
        super.init(proto: proto)
        self.Kind = .typedArray
    }

    public override var isOrdinaryLookup: bool { return false }

    /// IsOutOfBounds is IsTypedArrayOutOfBounds (§10.4.5.12).
    public var IsOutOfBounds: bool {
        if Buffer.Detached { return true }
        let bl = Buffer.ByteLength
        if ByteOffset > bl { return true }
        if FixedLength >= 0 && ByteOffset + FixedLength * Type.Size > bl { return true }
        return false
    }

    /// Length is TypedArrayLength: 0 when out of bounds.
    public var Length: int {
        if IsOutOfBounds { return 0 }
        if FixedLength >= 0 { return FixedLength }
        return (Buffer.ByteLength - ByteOffset) / Type.Size
    }

    public var ByteLength: int { return Length * Type.Size }

    func isValidIndex(_ d: float64) -> bool {
        if Buffer.Detached { return false }
        if d != d.rounded(.towardZero) { return false }
        if d == 0 && d.sign == .minus { return false }
        return d >= 0 && d < float64(Length)
    }

    /// GetElement reads element i (in range).
    public func GetElement(_ i: int) -> Value {
        let bits = readBits(Buffer.Data, ByteOffset + i * Type.Size, Type.Size, little: true)
        return bitsValue(Type, bits)
    }

    /// SetElement writes an already-converted value at i (in range).
    public func SetElement(_ i: int, _ v: Value) {
        writeBits(&Buffer.Data, ByteOffset + i * Type.Size, Type.Size, elementBits(Type, v), little: true)
    }

    /// numericIndex is CanonicalNumericIndexString for a key: the index,
    /// or nil for a key that is not numeric.
    func numericIndex(_ key: value.PropertyKey) -> float64? {
        switch key {
        case .index(let i):
            return float64(i)
        case .string(let s):
            if s.EqualsASCII("-0") { return -0.0 }
            let n = value.StringToNumber(s)
            if value.NumberToJSString(n).Equals(s) { return n }
            return nil
        case .symbol:
            return nil
        }
    }

    public override func GetOwnProperty(_ key: value.PropertyKey) throws -> object.PropertyDescriptor? {
        if let n = numericIndex(key) {
            if !isValidIndex(n) { return nil }
            return object.PropertyDescriptor.Data(GetElement(int(n)), writable: true, enumerable: true, configurable: true)
        }
        return try super.GetOwnProperty(key)
    }

    public override func HasProperty(_ key: value.PropertyKey) throws -> bool {
        if let n = numericIndex(key) { return isValidIndex(n) }
        return try HasPropertySlow(key)
    }

    public override func DefineOwnProperty(_ key: value.PropertyKey, _ desc: object.PropertyDescriptor) throws -> bool {
        if let n = numericIndex(key) {
            if !isValidIndex(n) { return false }
            if desc.Configurable == false || desc.Enumerable == false || desc.IsAccessor || desc.Writable == false { return false }
            if let v = desc.Value { try setIndexed(n, v) }
            return true
        }
        return try OrdinaryDefineOwnProperty(key, desc)
    }

    public override func Get(_ key: value.PropertyKey, _ receiver: Value) throws -> Value {
        if let n = numericIndex(key) {
            if !isValidIndex(n) { return .undefined }
            return GetElement(int(n))
        }
        return try GetSlow(key, receiver)
    }

    /// setIndexed is TypedArraySetElement: convert, then store if the
    /// index is still valid.
    func setIndexed(_ n: float64, _ v: Value) throws {
        let num = try toElementValue(Type, v)
        if isValidIndex(n) { SetElement(int(n), num) }
    }

    public override func Set(_ key: value.PropertyKey, _ v: Value, _ receiver: Value) throws -> bool {
        if let n = numericIndex(key) {
            if case .object(let ro) = receiver, ro === self {
                try setIndexed(n, v)
                return true
            }
            if !isValidIndex(n) { return true }
        }
        return try OrdinarySet(key, v, receiver)
    }

    public override func Delete(_ key: value.PropertyKey) throws -> bool {
        if let n = numericIndex(key) { return !isValidIndex(n) }
        return try super.Delete(key)
    }

    public override func OwnPropertyKeys() throws -> [value.PropertyKey] {
        var out: [value.PropertyKey] = []
        let len = Length
        var i = 0
        while i < len {
            out.append(.index(uint32(i)))
            i += 1
        }
        for k in OrdinaryOwnPropertyKeys() { out.append(k) }
        return out
    }
}

/// validTypedArray is ValidateTypedArray: a typed array not out of bounds.
func validTypedArray(_ v: Value, _ method: string) throws -> TypedArrayObject {
    guard case .object(let o) = v, let ta = o as? TypedArrayObject else {
        throw object.ThrowTypeError("this is not a typed array.")
    }
    if ta.IsOutOfBounds {
        throw object.ThrowTypeError("Cannot perform \(method) on a detached ArrayBuffer")
    }
    return ta
}

/// typedArrayCreate is TypedArrayCreateFromConstructor (§23.2.4.2):
/// construct and check the result, and its length when one was asked for.
func typedArrayCreate(_ c: object.JSObject, _ args: [Value]) throws -> TypedArrayObject {
    let v = try object.Construct(c, args)
    let ta = try validTypedArray(v, "construct")
    if args.count == 1, case .number(let n) = args[0], float64(ta.Length) < n {
        throw object.ThrowTypeError("Derived TypedArray constructor created an array which was too small")
    }
    return ta
}

/// speciesCreate is TypedArraySpeciesCreate (§23.2.4.1).
func speciesCreate(_ r: object.Realm, _ exemplar: TypedArrayObject, _ args: [Value]) throws -> TypedArrayObject {
    let dflt = r.Intrinsics[exemplar.Type.Name]!
    let c = try object.SpeciesConstructor(exemplar, dflt)
    let result = try typedArrayCreate(c, args)
    if result.Type.IsBigInt != exemplar.Type.IsBigInt {
        throw object.ThrowTypeError("Content type of the species-created typed array does not match")
    }
    return result
}

/// allocateTypedArray makes a typed array of t with a new buffer of length elements.
func allocateTypedArray(_ r: object.Realm, _ t: ElementType, _ proto: object.JSObject, _ length: int) throws -> TypedArrayObject {
    if length * t.Size > maxAllocation { throw object.ThrowRangeError("Invalid typed array length: \(length)") }
    let buf = try newBuffer(r, length * t.Size)
    let ta = TypedArrayObject(proto: proto, type: t, buffer: buf)
    ta.FixedLength = length
    return ta
}

func makeTypedArray(_ r: object.Realm, _ t: ElementType, _ args: [Value], _ newTarget: object.JSObject) throws -> TypedArrayObject {
    let proto = try object.GetPrototypeFromConstructor(newTarget, r.Intrinsics[t.Name + "Prototype"]!)
    let first = object.Arg(args, 0)
    guard case .object(let fo) = first else {
        return try allocateTypedArray(r, t, proto, try object.ToIndex(first))
    }
    if let src = fo as? TypedArrayObject {
        // InitializeTypedArrayFromTypedArray (§23.2.5.1.2).
        if src.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform Construct on a detached ArrayBuffer") }
        let len = src.Length
        if src.Type.IsBigInt != t.IsBigInt { throw object.ThrowTypeError("Content type of the source typed array does not match") }
        let ta = try allocateTypedArray(r, t, proto, len)
        var i = 0
        while i < len {
            ta.SetElement(i, src.GetElement(i))
            i += 1
        }
        return ta
    }
    if let buf = fo as? ArrayBufferObject {
        // InitializeTypedArrayFromArrayBuffer (§23.2.5.1.3).
        let size = t.Size
        let offset = try object.ToIndex(object.Arg(args, 1))
        if offset % size != 0 { throw object.ThrowRangeError("start offset of \(t.Name) should be a multiple of \(size)") }
        let lengthV = object.Arg(args, 2)
        var newLength = 0
        if !lengthV.IsUndefined { newLength = try object.ToIndex(lengthV) }
        if buf.Detached { throw object.ThrowTypeError("Cannot perform Construct on a detached ArrayBuffer") }
        let bufLen = buf.ByteLength
        let ta = TypedArrayObject(proto: proto, type: t, buffer: buf)
        ta.ByteOffset = offset
        if lengthV.IsUndefined && !buf.IsFixedLength {
            if offset > bufLen { throw object.ThrowRangeError("Start offset \(offset) is outside the bounds of the buffer") }
            ta.FixedLength = -1
            return ta
        }
        if lengthV.IsUndefined {
            if bufLen % size != 0 { throw object.ThrowRangeError("byte length of \(t.Name) should be a multiple of \(size)") }
            let nb = bufLen - offset
            if nb < 0 { throw object.ThrowRangeError("Start offset \(offset) is outside the bounds of the buffer") }
            ta.FixedLength = nb / size
        } else {
            if offset + newLength * size > bufLen { throw object.ThrowRangeError("Invalid typed array length: \(newLength)") }
            ta.FixedLength = newLength
        }
        return ta
    }
    // An iterable or an array-like.
    let usingIterator = try object.GetMethod(first, .symbol(value.SymIterator))
    var values: [Value] = []
    if !usingIterator.IsUndefined {
        values = try object.IterableToList(first)
        let ta = try allocateTypedArray(r, t, proto, values.count)
        var i = 0
        while i < values.count {
            try ta.setIndexed(float64(i), values[i])
            i += 1
        }
        return ta
    }
    let len = try object.LengthOfArrayLike(fo)
    let ta = try allocateTypedArray(r, t, proto, len)
    var i = 0
    while i < len {
        try ta.setIndexed(float64(i), try fo.Get(value.PropertyKey.FromNumber(float64(i)), first))
        i += 1
    }
    return ta
}

// MARK: comparison

/// compareElements is the default typed array sort order: numeric, -0
/// before +0, NaN last.
func compareElements(_ a: Value, _ b: Value) -> int {
    if case .bigint(let x) = a, case .bigint(let y) = b { return value.BigInt.Compare(x, y) }
    guard case .number(let x) = a, case .number(let y) = b else { return 0 }
    if x.isNaN { return y.isNaN ? 0 : 1 }
    if y.isNaN { return -1 }
    if x < y { return -1 }
    if x > y { return 1 }
    if x == 0 && y == 0 {
        let xn = x.sign == .minus
        let yn = y.sign == .minus
        if xn && !yn { return -1 }
        if !xn && yn { return 1 }
    }
    return 0
}

/// mergeSort sorts stably with a comparator that may throw.
func mergeSort(_ a: [Value], _ cmp: (Value, Value) throws -> int) throws -> [Value] {
    if a.count <= 1 { return a }
    var src = a
    var dst = a
    var width = 1
    let n = a.count
    while width < n {
        var lo = 0
        while lo < n {
            let mid = min(lo + width, n)
            let hi = min(lo + 2 * width, n)
            var i = lo
            var j = mid
            var k = lo
            while i < mid && j < hi {
                if try cmp(src[j], src[i]) < 0 {
                    dst[k] = src[j]
                    j += 1
                } else {
                    dst[k] = src[i]
                    i += 1
                }
                k += 1
            }
            while i < mid {
                dst[k] = src[i]
                i += 1
                k += 1
            }
            while j < hi {
                dst[k] = src[j]
                j += 1
                k += 1
            }
            lo += 2 * width
        }
        let t = src
        src = dst
        dst = t
        width *= 2
    }
    return src
}

// MARK: %TypedArray%

func installTypedArrays(_ r: object.Realm) {
    let tap = object.JSObject(proto: r.ObjectPrototype)
    r.Intrinsics["TypedArrayPrototype"] = tap
    let ta = r.Constructor("TypedArray", 0, prototype: tap, global: false) { _, _, _ in
        throw object.ThrowTypeError("Abstract class TypedArray not directly constructable")
    }
    r.Intrinsics["TypedArray"] = ta
    r.Getter(ta, .symbol(value.SymSpecies)) { thisV, _, _ in return thisV }

    indexed.TypedArrayLength = { o in
        guard let t = o as? TypedArrayObject else { return 0 }
        if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform %ArrayIteratorPrototype%.next on a detached ArrayBuffer") }
        return t.Length
    }

    // %TypedArray%.from and .of (§23.2.2).
    r.Method(ta, "from", 1) { thisV, args, _ in
        guard case .object(let c) = thisV, c.IsConstructor else { throw object.ThrowTypeError("\(object.Describe(thisV)) is not a constructor") }
        let source = object.Arg(args, 0)
        let mapfn = object.Arg(args, 1)
        let thisArg = object.Arg(args, 2)
        let mapping = !mapfn.IsUndefined
        if mapping && !mapfn.IsCallable { throw object.ThrowTypeError("\(object.Describe(mapfn)) is not a function") }
        let usingIterator = try object.GetMethod(source, .symbol(value.SymIterator))
        var values: [Value] = []
        if !usingIterator.IsUndefined {
            values = try object.IterableToList(source)
        } else {
            let o = try object.ToObject(source)
            let len = try object.LengthOfArrayLike(o)
            var i = 0
            while i < len {
                values.append(try o.Get(value.PropertyKey.FromNumber(float64(i)), .object(o)))
                i += 1
            }
        }
        let target = try typedArrayCreate(c, [.number(float64(values.count))])
        var k = 0
        while k < values.count {
            var v = values[k]
            if mapping { v = try object.Call(mapfn, thisArg, [v, .number(float64(k))]) }
            _ = try target.Set(value.PropertyKey.FromNumber(float64(k)), v, .object(target))
            k += 1
        }
        return .object(target)
    }
    r.Method(ta, "of", 0) { thisV, args, _ in
        guard case .object(let c) = thisV, c.IsConstructor else { throw object.ThrowTypeError("\(object.Describe(thisV)) is not a constructor") }
        let target = try typedArrayCreate(c, [.number(float64(args.count))])
        var k = 0
        while k < args.count {
            _ = try target.Set(value.PropertyKey.FromNumber(float64(k)), args[k], .object(target))
            k += 1
        }
        return .object(target)
    }

    // Accessors.
    r.Getter(tap, object.Key("buffer")) { thisV, _, _ in
        guard case .object(let o) = thisV, let t = o as? TypedArrayObject else { throw object.ThrowTypeError("this is not a typed array.") }
        return .object(t.Buffer)
    }
    r.Getter(tap, object.Key("byteLength")) { thisV, _, _ in
        guard case .object(let o) = thisV, let t = o as? TypedArrayObject else { throw object.ThrowTypeError("this is not a typed array.") }
        return .number(float64(t.ByteLength))
    }
    r.Getter(tap, object.Key("byteOffset")) { thisV, _, _ in
        guard case .object(let o) = thisV, let t = o as? TypedArrayObject else { throw object.ThrowTypeError("this is not a typed array.") }
        return .number(t.IsOutOfBounds ? 0 : float64(t.ByteOffset))
    }
    r.Getter(tap, object.Key("length")) { thisV, _, _ in
        guard case .object(let o) = thisV, let t = o as? TypedArrayObject else { throw object.ThrowTypeError("this is not a typed array.") }
        return .number(float64(t.Length))
    }
    r.Getter(tap, .symbol(value.SymToStringTag)) { thisV, _, _ in
        guard case .object(let o) = thisV, let t = o as? TypedArrayObject else { return .undefined }
        return .string(str.Name(t.Type.Name))
    }

    // Iteration.
    let values = r.Function("values", 0) { thisV, _, _ in
        return .object(indexed.CreateArrayIterator(r, try validTypedArray(thisV, "%TypedArray%.prototype.values"), .values))
    }
    tap.DefineData(object.Key("values"), .object(values), writable: true, enumerable: false, configurable: true)
    tap.DefineData(.symbol(value.SymIterator), .object(values), writable: true, enumerable: false, configurable: true)
    r.Method(tap, "keys", 0) { thisV, _, _ in
        return .object(indexed.CreateArrayIterator(r, try validTypedArray(thisV, "%TypedArray%.prototype.keys"), .keys))
    }
    r.Method(tap, "entries", 0) { thisV, _, _ in
        return .object(indexed.CreateArrayIterator(r, try validTypedArray(thisV, "%TypedArray%.prototype.entries"), .entries))
    }
    if let ats = try? r.ArrayPrototype.Get(object.Key("toString"), .object(r.ArrayPrototype)) {
        tap.DefineData(object.Key("toString"), ats, writable: true, enumerable: false, configurable: true)
    }

    func callback(_ v: Value) throws -> Value {
        if !v.IsCallable { throw object.ThrowTypeError("\(object.Describe(v)) is not a function") }
        return v
    }
    func idx(_ i: int) -> Value { return .number(float64(i)) }

    r.Method(tap, "at", 1) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.at")
        let len = t.Length
        let rel = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        let k = rel >= 0 ? rel : float64(len) + rel
        if k < 0 || k >= float64(len) { return .undefined }
        return try t.Get(value.PropertyKey.FromNumber(k), thisV)
    }
    r.Method(tap, "copyWithin", 2) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.copyWithin")
        let len = t.Length
        let to = try clampRelative(object.Arg(args, 0), len, 0)
        let from = try clampRelative(object.Arg(args, 1), len, 0)
        let fin = try clampRelative(object.Arg(args, 2), len, len)
        var count = min(fin - from, len - to)
        if count > 0 {
            if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform %TypedArray%.prototype.copyWithin on a detached ArrayBuffer") }
            let newLen = t.Length
            count = min(count, newLen - from, newLen - to)
            if count > 0 {
                let size = t.Type.Size
                let src = t.ByteOffset + from * size
                let dst = t.ByteOffset + to * size
                let bytes = Array(t.Buffer.Data[src..<(src + count * size)])
                var i = 0
                while i < bytes.count {
                    t.Buffer.Data[dst + i] = bytes[i]
                    i += 1
                }
            }
        }
        return thisV
    }
    r.Method(tap, "every", 1) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.every")
        let f = try callback(object.Arg(args, 0))
        let len = t.Length
        var i = 0
        while i < len {
            let v = try t.Get(value.PropertyKey.FromNumber(float64(i)), thisV)
            if !(try object.Call(f, object.Arg(args, 1), [v, idx(i), thisV])).Truthy { return .bool(false) }
            i += 1
        }
        return .bool(true)
    }
    r.Method(tap, "some", 1) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.some")
        let f = try callback(object.Arg(args, 0))
        let len = t.Length
        var i = 0
        while i < len {
            let v = try t.Get(value.PropertyKey.FromNumber(float64(i)), thisV)
            if (try object.Call(f, object.Arg(args, 1), [v, idx(i), thisV])).Truthy { return .bool(true) }
            i += 1
        }
        return .bool(false)
    }
    r.Method(tap, "fill", 1) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.fill")
        let len = t.Length
        let v = try toElementValue(t.Type, object.Arg(args, 0))
        let k = try clampRelative(object.Arg(args, 1), len, 0)
        var fin = try clampRelative(object.Arg(args, 2), len, len)
        if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform %TypedArray%.prototype.fill on a detached ArrayBuffer") }
        fin = min(fin, t.Length)
        var i = k
        while i < fin {
            t.SetElement(i, v)
            i += 1
        }
        return thisV
    }
    r.Method(tap, "filter", 1) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.filter")
        let f = try callback(object.Arg(args, 0))
        let len = t.Length
        var kept: [Value] = []
        var i = 0
        while i < len {
            let v = try t.Get(value.PropertyKey.FromNumber(float64(i)), thisV)
            if (try object.Call(f, object.Arg(args, 1), [v, idx(i), thisV])).Truthy { kept.append(v) }
            i += 1
        }
        let a = try speciesCreate(r, t, [.number(float64(kept.count))])
        var k = 0
        while k < kept.count {
            _ = try a.Set(value.PropertyKey.FromNumber(float64(k)), kept[k], .object(a))
            k += 1
        }
        return .object(a)
    }
    func findMethod(_ name: string, fromEnd: bool, wantIndex: bool) {
        r.Method(tap, name, 1) { thisV, args, _ in
            let t = try validTypedArray(thisV, "%TypedArray%.prototype.\(name)")
            let f = try callback(object.Arg(args, 0))
            let len = t.Length
            var i = fromEnd ? len - 1 : 0
            while fromEnd ? i >= 0 : i < len {
                let v = try t.Get(value.PropertyKey.FromNumber(float64(i)), thisV)
                if (try object.Call(f, object.Arg(args, 1), [v, idx(i), thisV])).Truthy {
                    return wantIndex ? idx(i) : v
                }
                i += fromEnd ? -1 : 1
            }
            return wantIndex ? .number(-1) : .undefined
        }
    }
    findMethod("find", fromEnd: false, wantIndex: false)
    findMethod("findIndex", fromEnd: false, wantIndex: true)
    findMethod("findLast", fromEnd: true, wantIndex: false)
    findMethod("findLastIndex", fromEnd: true, wantIndex: true)
    r.Method(tap, "forEach", 1) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.forEach")
        let f = try callback(object.Arg(args, 0))
        let len = t.Length
        var i = 0
        while i < len {
            let v = try t.Get(value.PropertyKey.FromNumber(float64(i)), thisV)
            _ = try object.Call(f, object.Arg(args, 1), [v, idx(i), thisV])
            i += 1
        }
        return .undefined
    }
    func searchMethod(_ name: string) {
        r.Method(tap, name, 1) { thisV, args, _ in
            let t = try validTypedArray(thisV, "%TypedArray%.prototype.\(name)")
            let len = t.Length
            if len == 0 { return name == "includes" ? .bool(false) : .number(-1) }
            let target = object.Arg(args, 0)
            if name == "lastIndexOf" {
                var n = float64(len - 1)
                if args.count > 1 { n = try object.ToIntegerOrInfinity(args[1]) }
                if n == -Double.infinity { return .number(-1) }
                var k = n >= 0 ? min(n, float64(len - 1)) : float64(len) + n
                while k >= 0 {
                    let key = value.PropertyKey.FromNumber(k)
                    if try t.HasProperty(key), object.StrictEquals(try t.Get(key, thisV), target) { return .number(k) }
                    k -= 1
                }
                return .number(-1)
            }
            var n = try object.ToIntegerOrInfinity(object.Arg(args, 1))
            if n == Double.infinity { return name == "includes" ? .bool(false) : .number(-1) }
            if n == -Double.infinity { n = 0 }
            var k = n >= 0 ? n : max(float64(len) + n, 0)
            while k < float64(len) {
                let key = value.PropertyKey.FromNumber(k)
                if name == "includes" {
                    if object.SameValueZero(try t.Get(key, thisV), target) { return .bool(true) }
                } else if try t.HasProperty(key), object.StrictEquals(try t.Get(key, thisV), target) {
                    return .number(k)
                }
                k += 1
            }
            return name == "includes" ? .bool(false) : .number(-1)
        }
    }
    searchMethod("includes")
    searchMethod("indexOf")
    searchMethod("lastIndexOf")
    r.Method(tap, "join", 1) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.join")
        let len = t.Length
        let sepV = object.Arg(args, 0)
        let sep = sepV.IsUndefined ? str.Name(",") : try object.ToString(sepV)
        var b = str.Builder()
        var i = 0
        while i < len {
            if i > 0 { b.Append(sep) }
            let v = try t.Get(value.PropertyKey.FromNumber(float64(i)), thisV)
            if !v.IsUndefined { b.Append(try object.ToString(v)) }
            i += 1
        }
        return .string(b.Build())
    }
    r.Method(tap, "toLocaleString", 0) { thisV, _, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.toLocaleString")
        let len = t.Length
        var b = str.Builder()
        var i = 0
        while i < len {
            if i > 0 { b.Append(str.Name(",")) }
            let v = try t.Get(value.PropertyKey.FromNumber(float64(i)), thisV)
            if !v.IsNullish { b.Append(try object.ToString(try object.Invoke(v, object.Key("toLocaleString"), []))) }
            i += 1
        }
        return .string(b.Build())
    }
    r.Method(tap, "map", 1) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.map")
        let f = try callback(object.Arg(args, 0))
        let len = t.Length
        let a = try speciesCreate(r, t, [.number(float64(len))])
        var i = 0
        while i < len {
            let v = try t.Get(value.PropertyKey.FromNumber(float64(i)), thisV)
            let mapped = try object.Call(f, object.Arg(args, 1), [v, idx(i), thisV])
            _ = try a.Set(value.PropertyKey.FromNumber(float64(i)), mapped, .object(a))
            i += 1
        }
        return .object(a)
    }
    func reduceMethod(_ name: string, right: bool) {
        r.Method(tap, name, 1) { thisV, args, _ in
            let t = try validTypedArray(thisV, "%TypedArray%.prototype.\(name)")
            let f = try callback(object.Arg(args, 0))
            let len = t.Length
            var k = right ? len - 1 : 0
            var acc: Value = .undefined
            if args.count >= 2 {
                acc = args[1]
            } else {
                if len == 0 { throw object.ThrowTypeError("Reduce of empty array with no initial value") }
                acc = try t.Get(value.PropertyKey.FromNumber(float64(k)), thisV)
                k += right ? -1 : 1
            }
            while right ? k >= 0 : k < len {
                let v = try t.Get(value.PropertyKey.FromNumber(float64(k)), thisV)
                acc = try object.Call(f, .undefined, [acc, v, idx(k), thisV])
                k += right ? -1 : 1
            }
            return acc
        }
    }
    reduceMethod("reduce", right: false)
    reduceMethod("reduceRight", right: true)
    r.Method(tap, "reverse", 0) { thisV, _, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.reverse")
        var lo = 0
        var hi = t.Length - 1
        while lo < hi {
            let a = t.GetElement(lo)
            t.SetElement(lo, t.GetElement(hi))
            t.SetElement(hi, a)
            lo += 1
            hi -= 1
        }
        return thisV
    }
    r.Method(tap, "toReversed", 0) { thisV, _, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.toReversed")
        let len = t.Length
        let a = try allocateTypedArray(r, t.Type, r.Intrinsics[t.Type.Name + "Prototype"]!, len)
        var i = 0
        while i < len {
            a.SetElement(i, t.GetElement(len - 1 - i))
            i += 1
        }
        return .object(a)
    }
    r.Method(tap, "set", 1) { thisV, args, _ in
        guard case .object(let o) = thisV, let t = o as? TypedArrayObject else { throw object.ThrowTypeError("this is not a typed array.") }
        let offD = try object.ToIntegerOrInfinity(object.Arg(args, 1))
        if offD < 0 { throw object.ThrowRangeError("offset is out of bounds") }
        let source = object.Arg(args, 0)
        if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform %TypedArray%.prototype.set on a detached ArrayBuffer") }
        let targetLen = t.Length
        if case .object(let so) = source, let src = so as? TypedArrayObject {
            if src.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform %TypedArray%.prototype.set on a detached ArrayBuffer") }
            let srcLen = src.Length
            if offD == Double.infinity || srcLen + int(offD) > targetLen { throw object.ThrowRangeError("offset is out of bounds") }
            if t.Type.IsBigInt != src.Type.IsBigInt { throw object.ThrowTypeError("Content type of the source typed array does not match") }
            // Read everything first: the two may share a buffer.
            var vals: [Value] = []
            var i = 0
            while i < srcLen {
                vals.append(src.GetElement(i))
                i += 1
            }
            let off = int(offD)
            i = 0
            while i < srcLen {
                t.SetElement(off + i, vals[i])
                i += 1
            }
            return .undefined
        }
        let so = try object.ToObject(source)
        let srcLen = try object.LengthOfArrayLike(so)
        if offD == Double.infinity || srcLen + int(offD) > targetLen { throw object.ThrowRangeError("offset is out of bounds") }
        let off = int(offD)
        var i = 0
        while i < srcLen {
            let v = try so.Get(value.PropertyKey.FromNumber(float64(i)), .object(so))
            try t.setIndexed(float64(off + i), v)
            i += 1
        }
        return .undefined
    }
    r.Method(tap, "slice", 2) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.slice")
        let len = t.Length
        let start = try clampRelative(object.Arg(args, 0), len, 0)
        let fin = try clampRelative(object.Arg(args, 1), len, len)
        let count = max(fin - start, 0)
        let a = try speciesCreate(r, t, [.number(float64(count))])
        if count > 0 {
            if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform %TypedArray%.prototype.slice on a detached ArrayBuffer") }
            let end = min(fin, t.Length)
            var k = start
            var n = 0
            while k < end {
                if a.Type == t.Type {
                    a.SetElement(n, t.GetElement(k))
                } else {
                    _ = try a.Set(value.PropertyKey.FromNumber(float64(n)), t.GetElement(k), .object(a))
                }
                k += 1
                n += 1
            }
        }
        return .object(a)
    }
    func sortedValues(_ t: TypedArrayObject, _ cmpV: Value) throws -> [Value] {
        let len = t.Length
        var vals: [Value] = []
        var i = 0
        while i < len {
            vals.append(t.GetElement(i))
            i += 1
        }
        if cmpV.IsUndefined { return try mergeSort(vals) { a, b in compareElements(a, b) } }
        return try mergeSort(vals) { a, b in
            let v = try object.ToNumber(try object.Call(cmpV, .undefined, [a, b]))
            if v.isNaN { return 0 }
            return v < 0 ? -1 : (v > 0 ? 1 : 0)
        }
    }
    r.Method(tap, "sort", 1) { thisV, args, _ in
        let cmpV = object.Arg(args, 0)
        if !cmpV.IsUndefined && !cmpV.IsCallable { throw object.ThrowTypeError("The comparison function must be either a function or undefined") }
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.sort")
        let sorted = try sortedValues(t, cmpV)
        let len = min(sorted.count, t.Length)
        var i = 0
        while i < len {
            t.SetElement(i, sorted[i])
            i += 1
        }
        return thisV
    }
    r.Method(tap, "toSorted", 1) { thisV, args, _ in
        let cmpV = object.Arg(args, 0)
        if !cmpV.IsUndefined && !cmpV.IsCallable { throw object.ThrowTypeError("The comparison function must be either a function or undefined") }
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.toSorted")
        let a = try allocateTypedArray(r, t.Type, r.Intrinsics[t.Type.Name + "Prototype"]!, t.Length)
        let sorted = try sortedValues(t, cmpV)
        var i = 0
        while i < sorted.count {
            a.SetElement(i, sorted[i])
            i += 1
        }
        return .object(a)
    }
    r.Method(tap, "subarray", 2) { thisV, args, _ in
        guard case .object(let o) = thisV, let t = o as? TypedArrayObject else { throw object.ThrowTypeError("this is not a typed array.") }
        let srcLen = t.Length
        let begin = try clampRelative(object.Arg(args, 0), srcLen, 0)
        let endV = object.Arg(args, 1)
        let size = t.Type.Size
        let beginByteOffset = t.ByteOffset + begin * size
        var cargs: [Value] = [.object(t.Buffer), .number(float64(beginByteOffset))]
        if t.FixedLength >= 0 || !endV.IsUndefined {
            let fin = try clampRelative(endV, srcLen, srcLen)
            cargs.append(.number(float64(max(fin - begin, 0))))
        }
        let dflt = r.Intrinsics[t.Type.Name]!
        let c = try object.SpeciesConstructor(t, dflt)
        let res = try typedArrayCreate(c, cargs)
        if res.Type.IsBigInt != t.Type.IsBigInt { throw object.ThrowTypeError("Content type of the species-created typed array does not match") }
        return .object(res)
    }
    r.Method(tap, "with", 2) { thisV, args, _ in
        let t = try validTypedArray(thisV, "%TypedArray%.prototype.with")
        let len = t.Length
        let rel = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        let actual = rel >= 0 ? rel : float64(len) + rel
        let v = try toElementValue(t.Type, object.Arg(args, 1))
        if !t.isValidIndex(actual) { throw object.ThrowRangeError("Invalid typed array index") }
        let a = try allocateTypedArray(r, t.Type, r.Intrinsics[t.Type.Name + "Prototype"]!, len)
        var i = 0
        while i < len {
            a.SetElement(i, float64(i) == actual ? v : t.GetElement(i))
            i += 1
        }
        return .object(a)
    }

    // The concrete constructors (§23.2.6).
    for t in allElementTypes {
        let proto = object.JSObject(proto: tap)
        r.Intrinsics[t.Name + "Prototype"] = proto
        let c = r.Constructor(t.Name, 3, prototype: proto) { _, args, nt in
            guard let n = nt else { throw object.ThrowTypeError("Constructor \(t.Name) requires 'new'") }
            return .object(try makeTypedArray(r, t, args, n))
        }
        c.Proto = ta
        r.Intrinsics[t.Name] = c
        let bpe = Value.number(float64(t.Size))
        c.DefineData(object.Key("BYTES_PER_ELEMENT"), bpe, writable: false, enumerable: false, configurable: false)
        proto.DefineData(object.Key("BYTES_PER_ELEMENT"), bpe, writable: false, enumerable: false, configurable: false)
    }
    installBase64(r)
}

// MARK: DataView (§25.3)

public final class DataViewObject: object.JSObject {
    public var Buffer: ArrayBufferObject
    public var ByteOffset: int = 0
    /// FixedLength is -1 for a view tracking a resizable buffer's length.
    public var FixedLength: int = -1

    public init(proto: object.JSObject?, buffer: ArrayBufferObject) {
        self.Buffer = buffer
        super.init(proto: proto)
        self.Kind = .dataView
    }

    public var IsOutOfBounds: bool {
        if Buffer.Detached { return true }
        let bl = Buffer.ByteLength
        if ByteOffset > bl { return true }
        if FixedLength >= 0 && ByteOffset + FixedLength > bl { return true }
        return false
    }

    public var ViewByteLength: int {
        return FixedLength >= 0 ? FixedLength : Buffer.ByteLength - ByteOffset
    }
}

func thisView(_ v: Value, _ method: string) throws -> DataViewObject {
    guard case .object(let o) = v, let d = o as? DataViewObject else {
        throw object.ThrowTypeError("Method DataView.prototype.\(method) called on incompatible receiver \(object.Describe(v))")
    }
    return d
}

func installDataView(_ r: object.Realm) {
    let dvp = object.JSObject(proto: r.ObjectPrototype)
    r.Intrinsics["DataViewPrototype"] = dvp
    let ctor = r.Constructor("DataView", 1, prototype: dvp) { _, args, nt in
        guard let n = nt else { throw object.ThrowTypeError("Constructor DataView requires 'new'") }
        guard case .object(let bo) = object.Arg(args, 0), let buf = bo as? ArrayBufferObject else {
            throw object.ThrowTypeError("First argument to DataView constructor must be an ArrayBuffer")
        }
        let offset = try object.ToIndex(object.Arg(args, 1))
        if buf.Detached { throw object.ThrowTypeError("Cannot perform DataView constructor on a detached ArrayBuffer") }
        var bufLen = buf.ByteLength
        if offset > bufLen { throw object.ThrowRangeError("Start offset \(offset) is outside the bounds of the buffer") }
        let lenV = object.Arg(args, 2)
        var viewLen = -1
        if lenV.IsUndefined {
            if buf.IsFixedLength { viewLen = bufLen - offset }
        } else {
            viewLen = try object.ToIndex(lenV)
            if offset + viewLen > bufLen { throw object.ThrowRangeError("Invalid DataView length \(viewLen)") }
        }
        let proto = try object.GetPrototypeFromConstructor(n, dvp)
        if buf.Detached { throw object.ThrowTypeError("Cannot perform DataView constructor on a detached ArrayBuffer") }
        bufLen = buf.ByteLength
        if offset > bufLen { throw object.ThrowRangeError("Start offset \(offset) is outside the bounds of the buffer") }
        if viewLen >= 0 && offset + viewLen > bufLen { throw object.ThrowRangeError("Invalid DataView length \(viewLen)") }
        let d = DataViewObject(proto: proto, buffer: buf)
        d.ByteOffset = offset
        d.FixedLength = viewLen
        return .object(d)
    }
    _ = ctor
    r.Getter(dvp, object.Key("buffer")) { thisV, _, _ in
        return .object(try thisView(thisV, "buffer").Buffer)
    }
    r.Getter(dvp, object.Key("byteLength")) { thisV, _, _ in
        let d = try thisView(thisV, "byteLength")
        if d.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform DataView.prototype.byteLength on a detached ArrayBuffer") }
        return .number(float64(d.ViewByteLength))
    }
    r.Getter(dvp, object.Key("byteOffset")) { thisV, _, _ in
        let d = try thisView(thisV, "byteOffset")
        if d.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform DataView.prototype.byteOffset on a detached ArrayBuffer") }
        return .number(float64(d.ByteOffset))
    }
    dvp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("DataView")), writable: false, enumerable: false, configurable: true)

    let types: [(string, ElementType)] = [("Int8", .int8), ("Uint8", .uint8), ("Int16", .int16), ("Uint16", .uint16), ("Int32", .int32), ("Uint32", .uint32), ("Float16", .float16), ("Float32", .float32), ("Float64", .float64), ("BigInt64", .bigInt64), ("BigUint64", .bigUint64)]
    for (name, t) in types {
        r.Method(dvp, "get" + name, 1) { thisV, args, _ in
            let d = try thisView(thisV, "get" + name)
            let index = try object.ToIndex(object.Arg(args, 0))
            let little = object.Arg(args, 1).Truthy
            if d.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform DataView.prototype.get\(name) on a detached ArrayBuffer") }
            if index + t.Size > d.ViewByteLength { throw object.ThrowRangeError("Offset is outside the bounds of the DataView") }
            let bits = readBits(d.Buffer.Data, d.ByteOffset + index, t.Size, little: little)
            return bitsValue(t, bits)
        }
        r.Method(dvp, "set" + name, 2) { thisV, args, _ in
            let d = try thisView(thisV, "set" + name)
            let index = try object.ToIndex(object.Arg(args, 0))
            let v = try toElementValue(t, object.Arg(args, 1))
            let little = object.Arg(args, 2).Truthy
            if d.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform DataView.prototype.set\(name) on a detached ArrayBuffer") }
            if index + t.Size > d.ViewByteLength { throw object.ThrowRangeError("Offset is outside the bounds of the DataView") }
            writeBits(&d.Buffer.Data, d.ByteOffset + index, t.Size, elementBits(t, v), little: little)
            return .undefined
        }
    }
}

// MARK: Atomics (§25.4)

/// waiter is a pending Atomics.waitAsync.
final class Waiter {
    let buffer: ArrayBufferObject
    let byteIndex: int
    let resolve: Value
    init(buffer: ArrayBufferObject, byteIndex: int, resolve: Value) {
        self.buffer = buffer
        self.byteIndex = byteIndex
        self.resolve = resolve
    }
}

var waiters: [Waiter] = []

func installAtomics(_ r: object.Realm) {
    let atomics = object.JSObject(proto: r.ObjectPrototype)
    r.DefineGlobal("Atomics", .object(atomics))
    atomics.DefineData(.symbol(value.SymToStringTag), .string(str.Name("Atomics")), writable: false, enumerable: false, configurable: true)

    /// validateIntegerTypedArray and ValidateAtomicAccess: the array and the index.
    func access(_ taV: Value, _ indexV: Value, waitable: bool = false) throws -> (TypedArrayObject, int) {
        let t = try validTypedArray(taV, "Atomics operation")
        if waitable {
            if t.Type != .int32 && t.Type != .bigInt64 { throw object.ThrowTypeError("[object Array] is not an int32 or BigInt64 typed array.") }
        } else {
            switch t.Type {
            case .int8, .uint8, .int16, .uint16, .int32, .uint32, .bigInt64, .bigUint64: break
            default: throw object.ThrowTypeError("[object Array] is not an integer shared typed array.")
            }
        }
        let i = try object.ToIndex(indexV)
        if i >= t.Length { throw object.ThrowRangeError("Invalid atomic access index") }
        return (t, i)
    }
    func rmw(_ name: string, _ op: @escaping (uint64, uint64) -> uint64) {
        r.Method(atomics, name, 3) { _, args, _ in
            let (t, i) = try access(object.Arg(args, 0), object.Arg(args, 1))
            let v = try toElementValue(t.Type, object.Arg(args, 2))
            if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform Atomics.\(name) on a detached ArrayBuffer") }
            let old = t.GetElement(i)
            let oldBits = elementBits(t.Type, old)
            let newBits = op(oldBits, elementBits(t.Type, v))
            t.SetElement(i, bitsValue(t.Type, newBits))
            return old
        }
    }
    rmw("add") { a, b in a &+ b }
    rmw("sub") { a, b in a &- b }
    rmw("and") { a, b in a & b }
    rmw("or") { a, b in a | b }
    rmw("xor") { a, b in a ^ b }
    rmw("exchange") { _, b in b }
    r.Method(atomics, "compareExchange", 4) { _, args, _ in
        let (t, i) = try access(object.Arg(args, 0), object.Arg(args, 1))
        let expected = try toElementValue(t.Type, object.Arg(args, 2))
        let replacement = try toElementValue(t.Type, object.Arg(args, 3))
        if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform Atomics.compareExchange on a detached ArrayBuffer") }
        let old = t.GetElement(i)
        let size = t.Type.Size
        let mask: uint64 = size == 8 ? 0xFFFFFFFFFFFFFFFF : (uint64(1) << uint64(size * 8)) - 1
        if elementBits(t.Type, old) & mask == elementBits(t.Type, expected) & mask {
            t.SetElement(i, replacement)
        }
        return old
    }
    r.Method(atomics, "load", 2) { _, args, _ in
        let (t, i) = try access(object.Arg(args, 0), object.Arg(args, 1))
        if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform Atomics.load on a detached ArrayBuffer") }
        return t.GetElement(i)
    }
    r.Method(atomics, "store", 3) { _, args, _ in
        let (t, i) = try access(object.Arg(args, 0), object.Arg(args, 1))
        var v: Value
        if t.Type.IsBigInt {
            v = .bigint(try object.ToBigInt(object.Arg(args, 2)))
        } else {
            let d = try object.ToIntegerOrInfinity(object.Arg(args, 2))
            v = .number(d == 0 ? 0 : d)
        }
        if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform Atomics.store on a detached ArrayBuffer") }
        t.SetElement(i, v)
        return v
    }
    r.Method(atomics, "isLockFree", 1) { _, args, _ in
        let n = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        return .bool(n == 1 || n == 2 || n == 4 || n == 8)
    }
    r.Method(atomics, "pause", 0) { _, args, _ in
        let n = object.Arg(args, 0)
        if !n.IsUndefined {
            guard case .number(let d) = n, d == d.rounded(.towardZero) else {
                throw object.ThrowTypeError("Atomics.pause argument must be undefined or an integer")
            }
        }
        return .undefined
    }
    // One agent, and it may not block (a window's main thread): wait
    // throws, as a browser's does; waitAsync settles on notify.
    r.Method(atomics, "wait", 4) { _, args, _ in
        let (t, _) = try access(object.Arg(args, 0), object.Arg(args, 1), waitable: true)
        if !t.Buffer.Shared { throw object.ThrowTypeError("[object Array] is not a shared typed array.") }
        throw object.ThrowTypeError("Atomics.wait cannot be called in this context")
    }
    r.Method(atomics, "waitAsync", 4) { _, args, _ in
        let (t, i) = try access(object.Arg(args, 0), object.Arg(args, 1), waitable: true)
        if !t.Buffer.Shared { throw object.ThrowTypeError("[object Array] is not a shared typed array.") }
        let v = try toElementValue(t.Type, object.Arg(args, 2))
        let timeoutV = object.Arg(args, 3)
        let q = timeoutV.IsUndefined ? Double.infinity : try object.ToNumber(timeoutV)
        let result = object.JSObject(proto: r.ObjectPrototype)
        if elementBits(t.Type, t.GetElement(i)) != elementBits(t.Type, v) {
            result.DefineData(object.Key("async"), .bool(false))
            result.DefineData(object.Key("value"), .string(str.Name("not-equal")))
            return .object(result)
        }
        if q.isNaN == false && q <= 0 {
            result.DefineData(object.Key("async"), .bool(false))
            result.DefineData(object.Key("value"), .string(str.Name("timed-out")))
            return .object(result)
        }
        let cap = try object.NewPromiseCapability(.object(r.Intrinsics["Promise"]!))
        waiters.append(Waiter(buffer: t.Buffer, byteIndex: t.ByteOffset + i * t.Type.Size, resolve: cap.Resolve))
        result.DefineData(object.Key("async"), .bool(true))
        result.DefineData(object.Key("value"), .object(cap.Promise))
        return .object(result)
    }
    r.Method(atomics, "notify", 3) { _, args, _ in
        let (t, i) = try access(object.Arg(args, 0), object.Arg(args, 1), waitable: true)
        let countV = object.Arg(args, 2)
        var count = Double.infinity
        if !countV.IsUndefined {
            let c = try object.ToIntegerOrInfinity(countV)
            count = c < 0 ? 0 : c
        }
        if !t.Buffer.Shared { return .number(0) }
        let byteIndex = t.ByteOffset + i * t.Type.Size
        var woken = 0
        var rest: [Waiter] = []
        for w in waiters {
            if float64(woken) < count && w.buffer === t.Buffer && w.byteIndex == byteIndex {
                _ = try object.Call(w.resolve, .undefined, [.string(str.Name("ok"))])
                woken += 1
            } else {
                rest.append(w)
            }
        }
        waiters = rest
        return .number(float64(woken))
    }
}

// MARK: Uint8Array base64 and hex (ES2026, §23.3)

let base64Chars: [uint8] = [uint8]("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
let hexChars: [uint8] = [uint8]("0123456789abcdef".utf8)

func thisUint8Array(_ v: Value, _ method: string) throws -> TypedArrayObject {
    guard case .object(let o) = v, let t = o as? TypedArrayObject, t.Type == .uint8 else {
        throw object.ThrowTypeError("Uint8Array.prototype.\(method) called on incompatible receiver \(object.Describe(v))")
    }
    return t
}

/// optionString reads a string option: its value, or dflt when undefined.
func optionString(_ opts: Value, _ name: string, _ dflt: string, _ allowed: [string]) throws -> string {
    guard case .object(let o) = opts else { return dflt }
    let v = try o.Get(object.Key(name), opts)
    if v.IsUndefined { return dflt }
    guard case .string(let s) = v else { throw object.ThrowTypeError("expected \(name) to be a string") }
    let t = s.String
    if !allowed.contains(t) { throw object.ThrowTypeError("expected \(name) to be one of \(allowed.joined(separator: ", "))") }
    return t
}

func optionsObject(_ v: Value) throws -> Value {
    if v.IsUndefined || v.IsObject { return v }
    throw object.ThrowTypeError("options must be an object")
}

func isAsciiSpace(_ c: uint16) -> bool {
    return c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0x20
}

struct DecodeResult {
    var read: int = 0
    var bytes: [uint8] = []
    var failed: bool = false
}

func base64Value(_ c: uint16) -> int {
    if c >= 0x41 && c <= 0x5A { return int(c - 0x41) }
    if c >= 0x61 && c <= 0x7A { return int(c - 0x61) + 26 }
    if c >= 0x30 && c <= 0x39 { return int(c - 0x30) + 52 }
    if c == 0x2B { return 62 }
    if c == 0x2F { return 63 }
    return -1
}

/// decodeChunk is DecodeBase64Chunk: nil when extra bits must be zero and are not.
func decodeChunk(_ chunk: [int], _ strict: bool) -> [uint8]? {
    var c = chunk
    let n = c.count
    while c.count < 4 { c.append(0) }
    let v = (c[0] << 18) | (c[1] << 12) | (c[2] << 6) | c[3]
    let b0 = uint8((v >> 16) & 0xFF)
    let b1 = uint8((v >> 8) & 0xFF)
    let b2 = uint8(v & 0xFF)
    if n == 2 {
        if strict && b1 != 0 { return nil }
        return [b0]
    }
    if n == 3 {
        if strict && b2 != 0 { return nil }
        return [b0, b1]
    }
    return [b0, b1, b2]
}

/// fromBase64 is FromBase64 (§23.3.2.1).
func fromBase64(_ s: [uint16], url: bool, _ lastChunk: string, _ maxLength: int) -> DecodeResult {
    var res = DecodeResult()
    if maxLength == 0 { return res }
    var chunk: [int] = []
    var index = 0
    let length = s.count
    func skip(_ i: int) -> int {
        var j = i
        while j < length && isAsciiSpace(s[j]) { j += 1 }
        return j
    }
    while true {
        index = skip(index)
        if index == length {
            if !chunk.isEmpty {
                if lastChunk == "stop-before-partial" { return res }
                if lastChunk == "loose" {
                    if chunk.count == 1 {
                        res.failed = true
                        return res
                    }
                    res.bytes.append(contentsOf: decodeChunk(chunk, false)!)
                } else {
                    res.failed = true
                    return res
                }
            }
            res.read = length
            return res
        }
        var c = s[index]
        index += 1
        if c == 0x3D {
            if chunk.count < 2 {
                res.failed = true
                return res
            }
            index = skip(index)
            if chunk.count == 2 {
                if index == length {
                    if lastChunk == "stop-before-partial" { return res }
                    res.failed = true
                    return res
                }
                if s[index] == 0x3D { index = skip(index + 1) }
            }
            if index < length {
                res.failed = true
                return res
            }
            guard let b = decodeChunk(chunk, lastChunk == "strict") else {
                res.failed = true
                return res
            }
            res.bytes.append(contentsOf: b)
            res.read = length
            return res
        }
        if url {
            if c == 0x2B || c == 0x2F {
                res.failed = true
                return res
            }
            if c == 0x2D { c = 0x2B } else if c == 0x5F { c = 0x2F }
        }
        let v = base64Value(c)
        if v < 0 {
            res.failed = true
            return res
        }
        let remaining = maxLength - res.bytes.count
        if (remaining == 1 && chunk.count == 2) || (remaining == 2 && chunk.count == 3) {
            return res
        }
        chunk.append(v)
        if chunk.count == 4 {
            res.bytes.append(contentsOf: decodeChunk(chunk, false)!)
            chunk = []
            res.read = index
            if res.bytes.count == maxLength { return res }
        }
    }
}

func hexValue(_ c: uint16) -> int {
    if c >= 0x30 && c <= 0x39 { return int(c - 0x30) }
    if c >= 0x61 && c <= 0x66 { return int(c - 0x61) + 10 }
    if c >= 0x41 && c <= 0x46 { return int(c - 0x41) + 10 }
    return -1
}

/// fromHex is FromHex (§23.3.2.2).
func fromHex(_ s: [uint16], _ maxLength: int) -> DecodeResult {
    var res = DecodeResult()
    if s.count % 2 != 0 {
        res.failed = true
        return res
    }
    while res.read < s.count && res.bytes.count < maxLength {
        let a = hexValue(s[res.read])
        let b = hexValue(s[res.read + 1])
        if a < 0 || b < 0 {
            res.failed = true
            return res
        }
        res.read += 2
        res.bytes.append(uint8(a * 16 + b))
    }
    return res
}

func installBase64(_ r: object.Realm) {
    let u8 = r.Intrinsics["Uint8Array"]!
    let u8p = r.Intrinsics["Uint8ArrayPrototype"]!
    func bytesOf(_ t: TypedArrayObject) throws -> [uint8] {
        if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform the operation on a detached ArrayBuffer") }
        let len = t.Length
        return Array(t.Buffer.Data[t.ByteOffset..<(t.ByteOffset + len)])
    }
    r.Method(u8p, "toBase64", 0) { thisV, args, _ in
        let t = try thisUint8Array(thisV, "toBase64")
        let opts = try optionsObject(object.Arg(args, 0))
        let alphabet = try optionString(opts, "alphabet", "base64", ["base64", "base64url"])
        var omit = false
        if case .object(let o) = opts { omit = try o.Get(object.Key("omitPadding"), opts).Truthy }
        let bytes = try bytesOf(t)
        var out: [uint16] = []
        var i = 0
        while i < bytes.count {
            let b0 = int(bytes[i])
            let b1 = i + 1 < bytes.count ? int(bytes[i + 1]) : 0
            let b2 = i + 2 < bytes.count ? int(bytes[i + 2]) : 0
            let v = (b0 << 16) | (b1 << 8) | b2
            let n = min(3, bytes.count - i)
            var k = 0
            while k < 4 {
                if k <= n {
                    var c = base64Chars[(v >> (18 - 6 * k)) & 63]
                    if alphabet == "base64url" {
                        if c == 0x2B { c = 0x2D } else if c == 0x2F { c = 0x5F }
                    }
                    out.append(uint16(c))
                } else if !omit {
                    out.append(0x3D)
                }
                k += 1
            }
            i += 3
        }
        return .string(str.JSString(out))
    }
    r.Method(u8p, "toHex", 0) { thisV, _, _ in
        let t = try thisUint8Array(thisV, "toHex")
        var out: [uint16] = []
        for b in try bytesOf(t) {
            out.append(uint16(hexChars[int(b >> 4)]))
            out.append(uint16(hexChars[int(b & 15)]))
        }
        return .string(str.JSString(out))
    }
    func result(_ read: int, _ written: int) -> Value {
        let o = object.JSObject(proto: r.ObjectPrototype)
        o.DefineData(object.Key("read"), .number(float64(read)))
        o.DefineData(object.Key("written"), .number(float64(written)))
        return .object(o)
    }
    func newUint8(_ bytes: [uint8]) throws -> Value {
        let a = try allocateTypedArray(r, .uint8, u8p, bytes.count)
        var i = 0
        while i < bytes.count {
            a.Buffer.Data[i] = bytes[i]
            i += 1
        }
        return .object(a)
    }
    r.Method(u8, "fromBase64", 1) { _, args, _ in
        guard case .string(let s) = object.Arg(args, 0) else { throw object.ThrowTypeError("Uint8Array.fromBase64 requires a string") }
        let opts = try optionsObject(object.Arg(args, 1))
        let alphabet = try optionString(opts, "alphabet", "base64", ["base64", "base64url"])
        let last = try optionString(opts, "lastChunkHandling", "loose", ["loose", "strict", "stop-before-partial"])
        let res = fromBase64(s.Units, url: alphabet == "base64url", last, Int.max)
        if res.failed { throw object.ThrowSyntaxError("Invalid base64 string") }
        return try newUint8(res.bytes)
    }
    r.Method(u8, "fromHex", 1) { _, args, _ in
        guard case .string(let s) = object.Arg(args, 0) else { throw object.ThrowTypeError("Uint8Array.fromHex requires a string") }
        let res = fromHex(s.Units, Int.max)
        if res.failed { throw object.ThrowSyntaxError("Invalid hex string") }
        return try newUint8(res.bytes)
    }
    r.Method(u8p, "setFromBase64", 1) { thisV, args, _ in
        let t = try thisUint8Array(thisV, "setFromBase64")
        guard case .string(let s) = object.Arg(args, 0) else { throw object.ThrowTypeError("Uint8Array.prototype.setFromBase64 requires a string") }
        let opts = try optionsObject(object.Arg(args, 1))
        let alphabet = try optionString(opts, "alphabet", "base64", ["base64", "base64url"])
        let last = try optionString(opts, "lastChunkHandling", "loose", ["loose", "strict", "stop-before-partial"])
        if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform setFromBase64 on a detached ArrayBuffer") }
        let res = fromBase64(s.Units, url: alphabet == "base64url", last, t.Length)
        var i = 0
        while i < res.bytes.count {
            t.Buffer.Data[t.ByteOffset + i] = res.bytes[i]
            i += 1
        }
        if res.failed { throw object.ThrowSyntaxError("Invalid base64 string") }
        return result(res.read, res.bytes.count)
    }
    r.Method(u8p, "setFromHex", 1) { thisV, args, _ in
        let t = try thisUint8Array(thisV, "setFromHex")
        guard case .string(let s) = object.Arg(args, 0) else { throw object.ThrowTypeError("Uint8Array.prototype.setFromHex requires a string") }
        if t.IsOutOfBounds { throw object.ThrowTypeError("Cannot perform setFromHex on a detached ArrayBuffer") }
        let res = fromHex(s.Units, t.Length)
        var i = 0
        while i < res.bytes.count {
            t.Buffer.Data[t.ByteOffset + i] = res.bytes[i]
            i += 1
        }
        if res.failed { throw object.ThrowSyntaxError("Invalid hex string") }
        return result(res.read, res.bytes.count)
    }
}

// installBuffers installs ArrayBuffer, SharedArrayBuffer, the typed
// arrays, DataView and Atomics.
func installBuffers(_ r: object.Realm) {
    installArrayBuffer(r)
    installTypedArrays(r)
    installDataView(r)
    installAtomics(r)
}
