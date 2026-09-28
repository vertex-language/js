package object

import (
    "js/str"
    "js/value"
)

/// ArrayObject is an Array exotic object (§10.4.2). Elements live in a
/// dense vector with .empty for holes; an array that gets an accessor or
/// a non-default attribute on an element, or a far-out index, moves its
/// elements into ordinary property storage and stays sparse.
public final class ArrayObject: JSObject {
    public var Dense: [Value] = []
    public var Length: uint32 = 0
    public var LengthWritable: bool = true
    public var Sparse: bool = false

    public override init(proto: JSObject?) {
        super.init(proto: proto)
        self.Kind = .array
    }

    /// IsDenseSimple says the elements are all in Dense.
    public var IsDenseSimple: bool {
        return !Sparse && Dense.count == int(Length)
    }

    public override var isOrdinaryLookup: bool { return false }

    func makeSparse() {
        if Sparse { return }
        var i = 0
        while i < Dense.count {
            if !Dense[i].IsEmpty {
                store(.index(uint32(i)), Slot(value: Dense[i], flags: fWritable | fEnumerable | fConfigurable))
            }
            i += 1
        }
        Dense = []
        Sparse = true
    }

    public override func GetOwnProperty(_ key: PropertyKey) throws -> PropertyDescriptor? {
        switch key {
        case .index(let i):
            if !Sparse {
                if int(i) < Dense.count && !Dense[int(i)].IsEmpty {
                    return PropertyDescriptor.Data(Dense[int(i)])
                }
                return nil
            }
        case .string:
            if key == keyLength {
                return PropertyDescriptor.Data(.number(float64(Length)), writable: LengthWritable, enumerable: false, configurable: false)
            }
        default:
            break
        }
        let s = find(key)
        return s < 0 ? nil : slots[s].Descriptor
    }

    public override func DefineOwnProperty(_ key: PropertyKey, _ desc: PropertyDescriptor) throws -> bool {
        if key == keyLength {
            return try setLength(desc)
        }
        guard case .index(let i) = key else {
            return try OrdinaryDefineOwnProperty(key, desc)
        }
        if i >= Length && !LengthWritable { return false }
        if !Sparse {
            let idx = int(i)
            let exists = idx < Dense.count && !Dense[idx].IsEmpty
            // A plain data element stays dense.
            let plain = !desc.IsAccessor && desc.Writable != false && desc.Enumerable != false && desc.Configurable != false
            let fullNew = desc.Writable == true && desc.Enumerable == true && desc.Configurable == true
            if plain && (exists || fullNew || (desc.Value != nil && desc.Writable == nil && desc.Enumerable == nil && desc.Configurable == nil && exists)) {
                if exists || fullNew {
                    if !exists && !Extensible { return false }
                    if idx < Dense.count {
                        if let v = desc.Value { Dense[idx] = v } else if !exists { Dense[idx] = .undefined }
                    } else if idx - Dense.count < 1 << 20 {
                        while Dense.count < idx { Dense.append(.empty) }
                        Dense.append(desc.Value ?? .undefined)
                    } else {
                        makeSparse()
                        return try defineSparse(i, desc)
                    }
                    if i >= Length { Length = i + 1 }
                    return true
                }
            }
            makeSparse()
        }
        return try defineSparse(i, desc)
    }

    func defineSparse(_ i: uint32, _ desc: PropertyDescriptor) throws -> bool {
        let ok = try OrdinaryDefineOwnProperty(.index(i), desc)
        if !ok { return false }
        if i >= Length { Length = i + 1 }
        return true
    }

    /// setLength is ArraySetLength (§10.4.2.4).
    func setLength(_ desc: PropertyDescriptor) throws -> bool {
        guard let v = desc.Value else {
            // Only attributes change.
            if desc.Configurable == true || desc.Enumerable == true || desc.IsAccessor { return false }
            if desc.Writable == true && !LengthWritable { return false }
            if desc.Writable == false { LengthWritable = false }
            return true
        }
        let n = try ToUint32(v)
        let num = try ToNumber(v)
        if float64(n) != num { throw ThrowRangeError("Invalid array length") }
        if desc.Configurable == true || desc.Enumerable == true || desc.IsAccessor { return false }
        if n != Length && !LengthWritable { return false }
        if desc.Writable == true && !LengthWritable { return false }
        let ok = truncate(to: n)
        if desc.Writable == false { LengthWritable = false }
        return ok
    }

    /// truncate deletes elements from the new length up; it stops at a
    /// non-configurable one.
    public func truncate(to n: uint32) -> bool {
        if n >= Length {
            Length = n
            return true
        }
        if !Sparse {
            while Dense.count > int(n) { _ = Dense.removeLast() }
            Length = n
            return true
        }
        var idxs: [uint32] = []
        for k in StoredKeys {
            if case .index(let i) = k, i >= n { idxs.append(i) }
        }
        idxs.sort()
        var j = idxs.count - 1
        while j >= 0 {
            let i = idxs[j]
            let s = find(.index(i))
            if s >= 0 && slots[s].Flags & fConfigurable == 0 {
                Length = i + 1
                return false
            }
            remove(.index(i))
            j -= 1
        }
        Length = n
        return true
    }

    public override func HasProperty(_ key: PropertyKey) throws -> bool {
        if case .index(let i) = key, !Sparse, int(i) < Dense.count, !Dense[int(i)].IsEmpty { return true }
        return try HasPropertySlow(key)
    }

    public override func Get(_ key: PropertyKey, _ receiver: Value) throws -> Value {
        if case .index(let i) = key, !Sparse {
            if int(i) < Dense.count {
                let v = Dense[int(i)]
                if !v.IsEmpty { return v }
            }
            guard let p = Proto else { return .undefined }
            return try p.Get(key, receiver)
        }
        if key == keyLength { return .number(float64(Length)) }
        return try GetSlow(key, receiver)
    }

    public override func Set(_ key: PropertyKey, _ v: Value, _ receiver: Value) throws -> bool {
        if case .index(let i) = key, !Sparse, case .object(let r) = receiver, r === self {
            let idx = int(i)
            if idx < Dense.count && !Dense[idx].IsEmpty {
                Dense[idx] = v
                return true
            }
            if idx == Dense.count && Extensible && LengthWritable && idx < int(uint32.max) && !protoHasIndexed() {
                Dense.append(v)
                if i >= Length { Length = i + 1 }
                return true
            }
        }
        return try OrdinarySet(key, v, receiver)
    }

    /// protoHasIndexed says whether an index could be found on the
    /// prototype chain (a setter there would take the assignment).
    func protoHasIndexed() -> bool {
        var p = Proto
        while let o = p {
            if !o.isOrdinaryLookup && !(o is ArrayObject) { return true }
            if let a = o as? ArrayObject {
                if !a.Dense.isEmpty || a.Sparse { return true }
            }
            if o.hasIndexKeys() { return true }
            p = o.Proto
        }
        return false
    }

    public override func Delete(_ key: PropertyKey) throws -> bool {
        if case .index(let i) = key, !Sparse {
            let idx = int(i)
            if idx < Dense.count {
                if idx == Dense.count - 1 {
                    _ = Dense.removeLast()
                    // Keep Length: deleting doesn't shorten an array.
                    while !Dense.isEmpty && Dense[Dense.count - 1].IsEmpty { _ = Dense.removeLast() }
                } else {
                    Dense[idx] = .empty
                }
            }
            return true
        }
        if key == keyLength { return false }
        return try super.Delete(key)
    }

    public override func OwnPropertyKeys() throws -> [PropertyKey] {
        var out: [PropertyKey] = []
        if !Sparse {
            var i = 0
            while i < Dense.count {
                if !Dense[i].IsEmpty { out.append(.index(uint32(i))) }
                i += 1
            }
        }
        let rest = OrdinaryOwnPropertyKeys()
        var restIdx = 0
        // Ordinary storage's indices (sparse arrays) come first, sorted.
        while restIdx < rest.count {
            if case .index = rest[restIdx] {
                out.append(rest[restIdx])
                restIdx += 1
            } else {
                break
            }
        }
        out.append(keyLength)
        while restIdx < rest.count {
            out.append(rest[restIdx])
            restIdx += 1
        }
        return out
    }

    /// Push appends without the generic protocol, for built-ins that made
    /// the array themselves.
    public func Push(_ v: Value) {
        if !Sparse && Dense.count == int(Length) {
            Dense.append(v)
            Length += 1
        } else {
            _ = try? DefineOwnProperty(.index(Length), PropertyDescriptor.Data(v))
        }
    }
}

/// ArgumentsObject is an arguments exotic object (§10.4.4). A mapped one
/// aliases its elements to the function's parameter slots in a context.
public final class ArgumentsObject: JSObject {
    /// Map holds, per argument index, the context slot it aliases, or -1.
    public var Map: [int] = []
    public var Env: Context? = nil

    public override init(proto: JSObject?) {
        super.init(proto: proto)
        self.Kind = .arguments
    }

    public override var isOrdinaryLookup: bool { return Env == nil }

    func mapped(_ key: PropertyKey) -> int {
        guard Env != nil, case .index(let i) = key, int(i) < Map.count else { return -1 }
        return Map[int(i)]
    }

    public override func GetOwnProperty(_ key: PropertyKey) throws -> PropertyDescriptor? {
        let s = find(key)
        if s < 0 { return nil }
        var d = slots[s].Descriptor
        let m = mapped(key)
        if m >= 0 { d.Value = Env!.Slots[m] }
        return d
    }

    public override func DefineOwnProperty(_ key: PropertyKey, _ desc: PropertyDescriptor) throws -> bool {
        let m = mapped(key)
        var d = desc
        if m >= 0 && d.IsData && d.Value == nil && d.Writable == false {
            d.Value = Env!.Slots[m]
        }
        if !(try OrdinaryDefineOwnProperty(key, d)) { return false }
        if m >= 0 {
            if d.IsAccessor {
                unmap(key)
            } else {
                if let v = d.Value { Env!.Slots[m] = v }
                if d.Writable == false { unmap(key) }
            }
        }
        return true
    }

    func unmap(_ key: PropertyKey) {
        if case .index(let i) = key, int(i) < Map.count { Map[int(i)] = -1 }
    }

    public override func Get(_ key: PropertyKey, _ receiver: Value) throws -> Value {
        let m = mapped(key)
        if m >= 0 && find(key) >= 0 { return Env!.Slots[m] }
        return try GetSlow(key, receiver)
    }

    public override func Set(_ key: PropertyKey, _ v: Value, _ receiver: Value) throws -> bool {
        let m = mapped(key)
        if m >= 0, case .object(let r) = receiver, r === self, find(key) >= 0 {
            Env!.Slots[m] = v
        }
        return try OrdinarySet(key, v, receiver)
    }

    public override func Delete(_ key: PropertyKey) throws -> bool {
        let ok = try super.Delete(key)
        if ok { unmap(key) }
        return ok
    }
}

/// StringObject is a String exotic object (§10.4.3): its code units are
/// read-only indexed properties.
public final class StringObject: JSObject {
    public let Str: str.JSString

    public init(_ s: str.JSString, proto: JSObject?) {
        self.Str = s
        super.init(proto: proto)
        self.Kind = .string
        self.PrimitiveValue = .string(s)
        DefineData(keyLength, .number(float64(s.Length)), writable: false, enumerable: false, configurable: false)
    }

    public override var isOrdinaryLookup: bool { return false }

    func stringProperty(_ key: PropertyKey) -> PropertyDescriptor? {
        guard case .index(let i) = key, int(i) < Str.Length else { return nil }
        return PropertyDescriptor.Data(.string(str.JSString([Str.At(int(i))])), writable: false, enumerable: true, configurable: false)
    }

    public override func GetOwnProperty(_ key: PropertyKey) throws -> PropertyDescriptor? {
        let s = find(key)
        if s >= 0 { return slots[s].Descriptor }
        return stringProperty(key)
    }

    public override func DefineOwnProperty(_ key: PropertyKey, _ desc: PropertyDescriptor) throws -> bool {
        if let cur = stringProperty(key) {
            return ValidateAndApply(key, false, desc, cur)
        }
        return try OrdinaryDefineOwnProperty(key, desc)
    }

    public override func OwnPropertyKeys() throws -> [PropertyKey] {
        var out: [PropertyKey] = []
        var i = 0
        while i < Str.Length {
            out.append(.index(uint32(i)))
            i += 1
        }
        let rest = OrdinaryOwnPropertyKeys()
        for k in rest {
            if case .index(let x) = k, int(x) < Str.Length { continue }
            out.append(k)
        }
        // Indices past the string's come before the other keys.
        var idx: [PropertyKey] = []
        var other: [PropertyKey] = []
        var j = Str.Length
        while j < out.count {
            if case .index = out[j] { idx.append(out[j]) } else { other.append(out[j]) }
            j += 1
        }
        var result: [PropertyKey] = []
        var k = 0
        while k < Str.Length { result.append(out[k]); k += 1 }
        result.append(contentsOf: idx)
        result.append(contentsOf: other)
        return result
    }
}
