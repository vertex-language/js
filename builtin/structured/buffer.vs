package structured

import (
    "gc"
    "js/object"
    "js/value"
)

public final class ArrayBufferRecord: gc.Cell {
    public var data: [uint8]
    public var byteLength: int

    public init(byteLength: int) {
        self.byteLength = byteLength
        self.data = Array(repeating: uint8(0), count: byteLength)
    }

    public init(bytes: [uint8]) {
        self.byteLength = bytes.count
        self.data = bytes
    }
}

public final class DataViewRecord: gc.Cell {
    public var buffer: object.JSObject
    public var byteOffset: int
    public var byteLength: int

    public init(buffer: object.JSObject, byteOffset: int, byteLength: int) {
        self.buffer = buffer
        self.byteOffset = byteOffset
        self.byteLength = byteLength
    }

    public override func Trace(with tracer: gc.Tracer) {
        super.Trace(with: tracer)
        tracer.Visit(buffer)
    }
}

public enum TypedArrayKind: int {
    case int8 = 1
    case uint8 = 2
    case uint8Clamped = 3
    case int16 = 4
    case uint16 = 5
    case int32 = 6
    case uint32 = 7
    case float32 = 8
    case float64 = 9
}

public final class TypedArrayRecord: gc.Cell {
    public var buffer: object.JSObject
    public var byteOffset: int
    public var length: int
    public var elementSize: int
    public var kind: TypedArrayKind

    public init(buffer: object.JSObject, byteOffset: int, length: int, elementSize: int, kind: TypedArrayKind) {
        self.buffer = buffer
        self.byteOffset = byteOffset
        self.length = length
        self.elementSize = elementSize
        self.kind = kind
    }

    public override func Trace(with tracer: gc.Tracer) {
        super.Trace(with: tracer)
        tracer.Visit(buffer)
    }
}

func readInt8(buf: ArrayBufferRecord, offset: int) -> value.Value {
    if offset < 0 || offset >= buf.byteLength { return value.Value.Undefined }
    let raw = buf.data[offset]
    let s = raw >= 128 ? int32(raw) - 256 : int32(raw)
    return value.Value.Int(s)
}

func readUint8(buf: ArrayBufferRecord, offset: int) -> value.Value {
    if offset < 0 || offset >= buf.byteLength { return value.Value.Undefined }
    return value.Value.Int(int32(buf.data[offset]))
}

func writeUint8(buf: inout ArrayBufferRecord, offset: int, val: uint8) {
    if offset >= 0 && offset < buf.byteLength {
        buf.data[offset] = val
    }
}

func readInt16(buf: ArrayBufferRecord, offset: int, le: bool) -> value.Value {
    if offset < 0 || offset + 1 >= buf.byteLength { return value.Value.Undefined }
    let b0 = uint16(buf.data[offset])
    let b1 = uint16(buf.data[offset + 1])
    let u = le ? (b0 | (b1 << 8)) : ((b0 << 8) | b1)
    let s = u >= 32768 ? int32(u) - 65536 : int32(u)
    return value.Value.Int(s)
}

func readUint16(buf: ArrayBufferRecord, offset: int, le: bool) -> value.Value {
    if offset < 0 || offset + 1 >= buf.byteLength { return value.Value.Undefined }
    let b0 = uint16(buf.data[offset])
    let b1 = uint16(buf.data[offset + 1])
    let u = le ? (b0 | (b1 << 8)) : ((b0 << 8) | b1)
    return value.Value.Int(int32(u))
}

func writeUint16(buf: inout ArrayBufferRecord, offset: int, val: uint16, le: bool) {
    if offset >= 0 && offset + 1 < buf.byteLength {
        if le {
            buf.data[offset] = uint8(val & 0xFF)
            buf.data[offset + 1] = uint8((val >> 8) & 0xFF)
        } else {
            buf.data[offset] = uint8((val >> 8) & 0xFF)
            buf.data[offset + 1] = uint8(val & 0xFF)
        }
    }
}

func readInt32(buf: ArrayBufferRecord, offset: int, le: bool) -> value.Value {
    if offset < 0 || offset + 3 >= buf.byteLength { return value.Value.Undefined }
    let b0 = uint32(buf.data[offset])
    let b1 = uint32(buf.data[offset + 1])
    let b2 = uint32(buf.data[offset + 2])
    let b3 = uint32(buf.data[offset + 3])
    let u = le ? (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)) : ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
    return value.Value.Int(int32(bitPattern: u))
}

func readUint32(buf: ArrayBufferRecord, offset: int, le: bool) -> value.Value {
    if offset < 0 || offset + 3 >= buf.byteLength { return value.Value.Undefined }
    let b0 = uint32(buf.data[offset])
    let b1 = uint32(buf.data[offset + 1])
    let b2 = uint32(buf.data[offset + 2])
    let b3 = uint32(buf.data[offset + 3])
    let u = le ? (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)) : ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
    return value.Value.Number(float64(u))
}

func writeUint32(buf: inout ArrayBufferRecord, offset: int, val: uint32, le: bool) {
    if offset >= 0 && offset + 3 < buf.byteLength {
        if le {
            buf.data[offset] = uint8(val & 0xFF)
            buf.data[offset + 1] = uint8((val >> 8) & 0xFF)
            buf.data[offset + 2] = uint8((val >> 16) & 0xFF)
            buf.data[offset + 3] = uint8((val >> 24) & 0xFF)
        } else {
            buf.data[offset] = uint8((val >> 24) & 0xFF)
            buf.data[offset + 1] = uint8((val >> 16) & 0xFF)
            buf.data[offset + 2] = uint8((val >> 8) & 0xFF)
            buf.data[offset + 3] = uint8(val & 0xFF)
        }
    }
}

func readFloat32(buf: ArrayBufferRecord, offset: int, le: bool) -> value.Value {
    if offset < 0 || offset + 3 >= buf.byteLength { return value.Value.Undefined }
    let b0 = uint32(buf.data[offset])
    let b1 = uint32(buf.data[offset + 1])
    let b2 = uint32(buf.data[offset + 2])
    let b3 = uint32(buf.data[offset + 3])
    let u = le ? (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)) : ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
    let f = float32(bitPattern: u)
    return value.Value.Number(float64(f))
}

func writeFloat32(buf: inout ArrayBufferRecord, offset: int, num: float64, le: bool) {
    let f = float32(num)
    let bits = f.bitPattern
    writeUint32(buf: &buf, offset: offset, val: bits, le: le)
}

func readFloat64(buf: ArrayBufferRecord, offset: int, le: bool) -> value.Value {
    if offset < 0 || offset + 7 >= buf.byteLength { return value.Value.Undefined }
    let b0 = uint64(buf.data[offset])
    let b1 = uint64(buf.data[offset + 1])
    let b2 = uint64(buf.data[offset + 2])
    let b3 = uint64(buf.data[offset + 3])
    let b4 = uint64(buf.data[offset + 4])
    let b5 = uint64(buf.data[offset + 5])
    let b6 = uint64(buf.data[offset + 6])
    let b7 = uint64(buf.data[offset + 7])

    let u: uint64 = le ?
        (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24) | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56)) :
        ((b0 << 56) | (b1 << 48) | (b2 << 40) | (b3 << 32) | (b4 << 24) | (b5 << 16) | (b6 << 8) | b7)

    let d = float64(bitPattern: u)
    return value.Value.Number(d)
}

func writeFloat64(buf: inout ArrayBufferRecord, offset: int, num: float64, le: bool) {
    if offset >= 0 && offset + 7 < buf.byteLength {
        let u = num.bitPattern
        if le {
            buf.data[offset] = uint8(u & 0xFF)
            buf.data[offset + 1] = uint8((u >> 8) & 0xFF)
            buf.data[offset + 2] = uint8((u >> 16) & 0xFF)
            buf.data[offset + 3] = uint8((u >> 24) & 0xFF)
            buf.data[offset + 4] = uint8((u >> 32) & 0xFF)
            buf.data[offset + 5] = uint8((u >> 40) & 0xFF)
            buf.data[offset + 6] = uint8((u >> 48) & 0xFF)
            buf.data[offset + 7] = uint8((u >> 56) & 0xFF)
        } else {
            buf.data[offset] = uint8((u >> 56) & 0xFF)
            buf.data[offset + 1] = uint8((u >> 48) & 0xFF)
            buf.data[offset + 2] = uint8((u >> 40) & 0xFF)
            buf.data[offset + 3] = uint8((u >> 32) & 0xFF)
            buf.data[offset + 4] = uint8((u >> 24) & 0xFF)
            buf.data[offset + 5] = uint8((u >> 16) & 0xFF)
            buf.data[offset + 6] = uint8((u >> 8) & 0xFF)
            buf.data[offset + 7] = uint8(u & 0xFF)
        }
    }
}

func clampUint8(_ num: float64) -> uint8 {
    if num.isNaN || num <= 0.0 { return 0 }
    if num >= 255.0 { return 255 }
    return uint8(int32(num.rounded()))
}

func registerBuffers(into realm: object.Realm) {
    let g = realm.GlobalObject

    // 1. ArrayBuffer
    let arrayBufferProto = realm.NewObject()
    arrayBufferProto.InternalTag = "ArrayBuffer"

    let arrayBufferCtor = realm.NewFunction(name: "ArrayBuffer") { r, _, args in
        let len = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let byteLen = len < 0 ? 0 : len
        let buf = r.NewObject(prototype: arrayBufferProto)
        buf.InternalTag = "ArrayBuffer"
        let rec = ArrayBufferRecord(byteLength: byteLen)
        buf.NativeData = rec
        buf.Set("byteLength", value.Value.Int(int32(byteLen)))
        return value.Value.Object(buf)
    }
    arrayBufferCtor.Set("prototype", value.Value.Object(arrayBufferProto))

    // ArrayBuffer.isView
    arrayBufferCtor.Set("isView", value.Value.Object(realm.NewFunction(name: "isView") { _, _, args in
        if args.isEmpty || !args[0].IsObject { return value.Value.False }
        if let obj = args[0].ObjVal as? object.JSObject {
            let isView = (obj.NativeData is DataViewRecord) || (obj.NativeData is TypedArrayRecord)
            return value.Value.Boolean(isView)
        }
        return value.Value.False
    }))

    // ArrayBuffer.prototype.slice
    arrayBufferProto.Set("slice", value.Value.Object(realm.NewFunction(name: "slice") { r, thisVal, args in
        guard let obj = thisVal.ObjVal as? object.JSObject, let rec = obj.NativeData as? ArrayBufferRecord else {
            return value.Value.Undefined
        }
        let total = rec.byteLength
        var start = args.count > 0 ? Int(args[0].ToInt32()) : 0
        var end = args.count > 1 ? Int(args[1].ToInt32()) : total
        if start < 0 { start = max(0, total + start) } else { start = min(total, start) }
        if end < 0 { end = max(0, total + end) } else { end = min(total, end) }
        let newLen = max(0, end - start)

        var newBytes: [uint8] = []
        if newLen > 0 {
            for i in start..<end {
                newBytes.append(rec.data[i])
            }
        }
        let newBuf = r.NewObject(prototype: arrayBufferProto)
        newBuf.InternalTag = "ArrayBuffer"
        newBuf.NativeData = ArrayBufferRecord(bytes: newBytes)
        newBuf.Set("byteLength", value.Value.Int(int32(newLen)))
        return value.Value.Object(newBuf)
    }))

    g.Set("ArrayBuffer", value.Value.Object(arrayBufferCtor))
    realm.Heap.Roots.AddRoot(arrayBufferProto)
    realm.Heap.Roots.AddRoot(arrayBufferCtor)

    // 2. DataView
    let dataViewProto = realm.NewObject()
    dataViewProto.InternalTag = "DataView"

    let dataViewCtor = realm.NewFunction(name: "DataView") { r, _, args in
        guard !args.isEmpty, let bufObj = args[0].ObjVal as? object.JSObject, let bufRec = bufObj.NativeData as? ArrayBufferRecord else {
            return value.Value.Undefined
        }
        let offset = args.count > 1 ? Int(args[1].ToInt32()) : 0
        let byteOffset = max(0, min(bufRec.byteLength, offset))
        let maxLen = bufRec.byteLength - byteOffset
        let len = args.count > 2 ? Int(args[2].ToInt32()) : maxLen
        let byteLength = max(0, min(maxLen, len))

        let dv = r.NewObject(prototype: dataViewProto)
        dv.InternalTag = "DataView"
        dv.NativeData = DataViewRecord(buffer: bufObj, byteOffset: byteOffset, byteLength: byteLength)
        dv.Set("buffer", value.Value.Object(bufObj))
        dv.Set("byteOffset", value.Value.Int(int32(byteOffset)))
        dv.Set("byteLength", value.Value.Int(int32(byteLength)))
        return value.Value.Object(dv)
    }
    dataViewCtor.Set("prototype", value.Value.Object(dataViewProto))

    func getDV(_ thisVal: value.Value) -> (DataViewRecord, ArrayBufferRecord)? {
        guard let obj = thisVal.ObjVal as? object.JSObject,
              let dv = obj.NativeData as? DataViewRecord,
              let buf = dv.buffer.NativeData as? ArrayBufferRecord else {
            return nil
        }
        return (dv, buf)
    }

    // DataView getters & setters
    dataViewProto.Set("getInt8", value.Value.Object(realm.NewFunction(name: "getInt8") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        return readInt8(buf: pair.1, offset: pair.0.byteOffset + idx)
    }))
    dataViewProto.Set("getUint8", value.Value.Object(realm.NewFunction(name: "getUint8") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        return readUint8(buf: pair.1, offset: pair.0.byteOffset + idx)
    }))
    dataViewProto.Set("setInt8", value.Value.Object(realm.NewFunction(name: "setInt8") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let v = args.count > 1 ? uint8(Int(args[1].ToInt32()) & 0xFF) : 0
        var buf = pair.1
        writeUint8(buf: &buf, offset: pair.0.byteOffset + idx, val: v)
        return value.Value.Undefined
    }))
    dataViewProto.Set("setUint8", value.Value.Object(realm.NewFunction(name: "setUint8") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let v = args.count > 1 ? uint8(Int(args[1].ToInt32()) & 0xFF) : 0
        var buf = pair.1
        writeUint8(buf: &buf, offset: pair.0.byteOffset + idx, val: v)
        return value.Value.Undefined
    }))

    dataViewProto.Set("getInt16", value.Value.Object(realm.NewFunction(name: "getInt16") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let le = args.count > 1 ? args[1].ToBoolean() : false
        return readInt16(buf: pair.1, offset: pair.0.byteOffset + idx, le: le)
    }))
    dataViewProto.Set("getUint16", value.Value.Object(realm.NewFunction(name: "getUint16") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let le = args.count > 1 ? args[1].ToBoolean() : false
        return readUint16(buf: pair.1, offset: pair.0.byteOffset + idx, le: le)
    }))
    dataViewProto.Set("setInt16", value.Value.Object(realm.NewFunction(name: "setInt16") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let v = args.count > 1 ? uint16(Int(args[1].ToInt32()) & 0xFFFF) : 0
        let le = args.count > 2 ? args[2].ToBoolean() : false
        var buf = pair.1
        writeUint16(buf: &buf, offset: pair.0.byteOffset + idx, val: v, le: le)
        return value.Value.Undefined
    }))
    dataViewProto.Set("setUint16", value.Value.Object(realm.NewFunction(name: "setUint16") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let v = args.count > 1 ? uint16(Int(args[1].ToInt32()) & 0xFFFF) : 0
        let le = args.count > 2 ? args[2].ToBoolean() : false
        var buf = pair.1
        writeUint16(buf: &buf, offset: pair.0.byteOffset + idx, val: v, le: le)
        return value.Value.Undefined
    }))

    dataViewProto.Set("getInt32", value.Value.Object(realm.NewFunction(name: "getInt32") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let le = args.count > 1 ? args[1].ToBoolean() : false
        return readInt32(buf: pair.1, offset: pair.0.byteOffset + idx, le: le)
    }))
    dataViewProto.Set("getUint32", value.Value.Object(realm.NewFunction(name: "getUint32") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let le = args.count > 1 ? args[1].ToBoolean() : false
        return readUint32(buf: pair.1, offset: pair.0.byteOffset + idx, le: le)
    }))
    dataViewProto.Set("setInt32", value.Value.Object(realm.NewFunction(name: "setInt32") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let v = args.count > 1 ? uint32(bitPattern: args[1].ToInt32()) : 0
        let le = args.count > 2 ? args[2].ToBoolean() : false
        var buf = pair.1
        writeUint32(buf: &buf, offset: pair.0.byteOffset + idx, val: v, le: le)
        return value.Value.Undefined
    }))
    dataViewProto.Set("setUint32", value.Value.Object(realm.NewFunction(name: "setUint32") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let v = args.count > 1 ? uint32(bitPattern: args[1].ToInt32()) : 0
        let le = args.count > 2 ? args[2].ToBoolean() : false
        var buf = pair.1
        writeUint32(buf: &buf, offset: pair.0.byteOffset + idx, val: v, le: le)
        return value.Value.Undefined
    }))

    dataViewProto.Set("getFloat32", value.Value.Object(realm.NewFunction(name: "getFloat32") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let le = args.count > 1 ? args[1].ToBoolean() : false
        return readFloat32(buf: pair.1, offset: pair.0.byteOffset + idx, le: le)
    }))
    dataViewProto.Set("setFloat32", value.Value.Object(realm.NewFunction(name: "setFloat32") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let num = args.count > 1 ? args[1].ToNumber() : 0.0
        let le = args.count > 2 ? args[2].ToBoolean() : false
        var buf = pair.1
        writeFloat32(buf: &buf, offset: pair.0.byteOffset + idx, num: num, le: le)
        return value.Value.Undefined
    }))

    dataViewProto.Set("getFloat64", value.Value.Object(realm.NewFunction(name: "getFloat64") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let le = args.count > 1 ? args[1].ToBoolean() : false
        return readFloat64(buf: pair.1, offset: pair.0.byteOffset + idx, le: le)
    }))
    dataViewProto.Set("setFloat64", value.Value.Object(realm.NewFunction(name: "setFloat64") { _, thisVal, args in
        guard let pair = getDV(thisVal) else { return value.Value.Undefined }
        let idx = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let num = args.count > 1 ? args[1].ToNumber() : 0.0
        let le = args.count > 2 ? args[2].ToBoolean() : false
        var buf = pair.1
        writeFloat64(buf: &buf, offset: pair.0.byteOffset + idx, num: num, le: le)
        return value.Value.Undefined
    }))

    g.Set("DataView", value.Value.Object(dataViewCtor))
    realm.Heap.Roots.AddRoot(dataViewProto)
    realm.Heap.Roots.AddRoot(dataViewCtor)

    // 3. TypedArray Family Setup
    struct TypedArraySpec {
        var name: string
        var kind: TypedArrayKind
        var elementSize: int
    }

    let specs: [TypedArraySpec] = [
        TypedArraySpec(name: "Int8Array", kind: .int8, elementSize: 1),
        TypedArraySpec(name: "Uint8Array", kind: .uint8, elementSize: 1),
        TypedArraySpec(name: "Uint8ClampedArray", kind: .uint8Clamped, elementSize: 1),
        TypedArraySpec(name: "Int16Array", kind: .int16, elementSize: 2),
        TypedArraySpec(name: "Uint16Array", kind: .uint16, elementSize: 2),
        TypedArraySpec(name: "Int32Array", kind: .int32, elementSize: 4),
        TypedArraySpec(name: "Uint32Array", kind: .uint32, elementSize: 4),
        TypedArraySpec(name: "Float32Array", kind: .float32, elementSize: 4),
        TypedArraySpec(name: "Float64Array", kind: .float64, elementSize: 8)
    ]

    for spec in specs {
        let proto = realm.NewObject()
        proto.InternalTag = spec.name

        let name = spec.name
        let kind = spec.kind
        let elSize = spec.elementSize

        let ctor = realm.NewFunction(name: name) { r, _, args in
            var bufferObj: object.JSObject
            var byteOffset = 0
            var length = 0

            if args.isEmpty {
                // new TypedArray() -> 0 length
                let ab = r.NewObject(prototype: arrayBufferProto)
                ab.InternalTag = "ArrayBuffer"
                ab.NativeData = ArrayBufferRecord(byteLength: 0)
                ab.Set("byteLength", value.Value.Int(0))
                bufferObj = ab
            } else if args[0].IsNumber {
                // new TypedArray(length)
                length = max(0, Int(args[0].ToInt32()))
                let byteLen = length * elSize
                let ab = r.NewObject(prototype: arrayBufferProto)
                ab.InternalTag = "ArrayBuffer"
                ab.NativeData = ArrayBufferRecord(byteLength: byteLen)
                ab.Set("byteLength", value.Value.Int(int32(byteLen)))
                bufferObj = ab
            } else if args[0].IsObject, let firstObj = args[0].ObjVal as? object.JSObject {
                if let bufRec = firstObj.NativeData as? ArrayBufferRecord {
                    // new TypedArray(buffer, byteOffset?, length?)
                    bufferObj = firstObj
                    let off = args.count > 1 ? Int(args[1].ToInt32()) : 0
                    byteOffset = max(0, min(bufRec.byteLength, off))
                    let remainingBytes = bufRec.byteLength - byteOffset
                    if args.count > 2 {
                        length = max(0, min(remainingBytes / elSize, Int(args[2].ToInt32())))
                    } else {
                        length = remainingBytes / elSize
                    }
                } else if firstObj.InternalTag == "Array" || (firstObj.NativeData is TypedArrayRecord) {
                    // new TypedArray(arrayLike)
                    let srcLen = Int(firstObj.Get("length").ToInt32())
                    length = max(0, srcLen)
                    let byteLen = length * elSize
                    let ab = r.NewObject(prototype: arrayBufferProto)
                    ab.InternalTag = "ArrayBuffer"
                    ab.NativeData = ArrayBufferRecord(byteLength: byteLen)
                    ab.Set("byteLength", value.Value.Int(int32(byteLen)))
                    bufferObj = ab

                    // Copy initial elements
                    var bufRec = ab.NativeData as! ArrayBufferRecord
                    for i in 0..<length {
                        let elVal = firstObj.GetElement(i)
                        let offset = i * elSize
                        switch kind {
                        case .int8:
                            writeUint8(buf: &bufRec, offset: offset, val: uint8(Int(elVal.ToInt32()) & 0xFF))
                        case .uint8:
                            writeUint8(buf: &bufRec, offset: offset, val: uint8(Int(elVal.ToInt32()) & 0xFF))
                        case .uint8Clamped:
                            writeUint8(buf: &bufRec, offset: offset, val: clampUint8(elVal.ToNumber()))
                        case .int16, .uint16:
                            writeUint16(buf: &bufRec, offset: offset, val: uint16(Int(elVal.ToInt32()) & 0xFFFF), le: true)
                        case .int32, .uint32:
                            writeUint32(buf: &bufRec, offset: offset, val: uint32(bitPattern: elVal.ToInt32()), le: true)
                        case .float32:
                            writeFloat32(buf: &bufRec, offset: offset, num: elVal.ToNumber(), le: true)
                        case .float64:
                            writeFloat64(buf: &bufRec, offset: offset, num: elVal.ToNumber(), le: true)
                        }
                    }
                } else {
                    let ab = r.NewObject(prototype: arrayBufferProto)
                    ab.InternalTag = "ArrayBuffer"
                    ab.NativeData = ArrayBufferRecord(byteLength: 0)
                    ab.Set("byteLength", value.Value.Int(0))
                    bufferObj = ab
                }
            } else {
                let ab = r.NewObject(prototype: arrayBufferProto)
                ab.InternalTag = "ArrayBuffer"
                ab.NativeData = ArrayBufferRecord(byteLength: 0)
                ab.Set("byteLength", value.Value.Int(0))
                bufferObj = ab
            }

            let byteLength = length * elSize
            let rec = TypedArrayRecord(buffer: bufferObj, byteOffset: byteOffset, length: length, elementSize: elSize, kind: kind)

            let typedArr = r.NewObject(prototype: proto)
            typedArr.InternalTag = name
            typedArr.NativeData = rec
            typedArr.Set("buffer", value.Value.Object(bufferObj))
            typedArr.Set("byteOffset", value.Value.Int(int32(byteOffset)))
            typedArr.Set("byteLength", value.Value.Int(int32(byteLength)))
            typedArr.Set("length", value.Value.Int(int32(length)))
            typedArr.Set("BYTES_PER_ELEMENT", value.Value.Int(int32(elSize)))

            // Attach ElementHook for transparent index read/write
            typedArr.ElementHook = { selfObj, idx, writeVal in
                guard let rec = selfObj.NativeData as? TypedArrayRecord,
                      let buf = rec.buffer.NativeData as? ArrayBufferRecord else {
                    return nil
                }
                if idx < 0 || idx >= rec.length { return nil }
                let offset = rec.byteOffset + idx * rec.elementSize

                if let w = writeVal {
                    // Write
                    var mutBuf = buf
                    switch rec.kind {
                    case .int8, .uint8:
                        writeUint8(buf: &mutBuf, offset: offset, val: uint8(Int(w.ToInt32()) & 0xFF))
                    case .uint8Clamped:
                        writeUint8(buf: &mutBuf, offset: offset, val: clampUint8(w.ToNumber()))
                    case .int16, .uint16:
                        writeUint16(buf: &mutBuf, offset: offset, val: uint16(Int(w.ToInt32()) & 0xFFFF), le: true)
                    case .int32, .uint32:
                        writeUint32(buf: &mutBuf, offset: offset, val: uint32(bitPattern: w.ToInt32()), le: true)
                    case .float32:
                        writeFloat32(buf: &mutBuf, offset: offset, num: w.ToNumber(), le: true)
                    case .float64:
                        writeFloat64(buf: &mutBuf, offset: offset, num: w.ToNumber(), le: true)
                    }
                    return w
                } else {
                    // Read
                    switch rec.kind {
                    case .int8:
                        return readInt8(buf: buf, offset: offset)
                    case .uint8, .uint8Clamped:
                        return readUint8(buf: buf, offset: offset)
                    case .int16:
                        return readInt16(buf: buf, offset: offset, le: true)
                    case .uint16:
                        return readUint16(buf: buf, offset: offset, le: true)
                    case .int32:
                        return readInt32(buf: buf, offset: offset, le: true)
                    case .uint32:
                        return readUint32(buf: buf, offset: offset, le: true)
                    case .float32:
                        return readFloat32(buf: buf, offset: offset, le: true)
                    case .float64:
                        return readFloat64(buf: buf, offset: offset, le: true)
                    }
                }
            }

            return value.Value.Object(typedArr)
        }

        ctor.Set("prototype", value.Value.Object(proto))
        ctor.Set("BYTES_PER_ELEMENT", value.Value.Int(int32(elSize)))

        // TypedArray.prototype.subarray
        proto.Set("subarray", value.Value.Object(realm.NewFunction(name: "subarray") { r, thisVal, args in
            guard let obj = thisVal.ObjVal as? object.JSObject,
                  let rec = obj.NativeData as? TypedArrayRecord else {
                return value.Value.Undefined
            }
            let total = rec.length
            var start = args.count > 0 ? Int(args[0].ToInt32()) : 0
            var end = args.count > 1 ? Int(args[1].ToInt32()) : total
            if start < 0 { start = max(0, total + start) } else { start = min(total, start) }
            if end < 0 { end = max(0, total + end) } else { end = min(total, end) }
            let newLen = max(0, end - start)
            let newByteOffset = rec.byteOffset + start * rec.elementSize

            let subArrCtor = r.GlobalObject.Get(name).ObjVal as? object.JSObject
            if let c = subArrCtor, let callable = c.Callable {
                return try r.Call(c, args: [value.Value.Object(rec.buffer), value.Value.Int(int32(newByteOffset)), value.Value.Int(int32(newLen))])
            }
            return value.Value.Undefined
        }))

        // TypedArray.prototype.set
        proto.Set("set", value.Value.Object(realm.NewFunction(name: "set") { _, thisVal, args in
            guard let selfObj = thisVal.ObjVal as? object.JSObject,
                  let selfRec = selfObj.NativeData as? TypedArrayRecord,
                  !args.isEmpty,
                  let srcObj = args[0].ObjVal as? object.JSObject else {
                return value.Value.Undefined
            }
            let offset = args.count > 1 ? max(0, Int(args[1].ToInt32())) : 0
            let srcLen = Int(srcObj.Get("length").ToInt32())

            for i in 0..<srcLen {
                let targetIdx = offset + i
                if targetIdx < selfRec.length {
                    let v = srcObj.GetElement(i)
                    selfObj.SetElement(targetIdx, v)
                }
            }
            return value.Value.Undefined
        }))

        g.Set(name, value.Value.Object(ctor))
        realm.Heap.Roots.AddRoot(proto)
        realm.Heap.Roots.AddRoot(ctor)
    }
}
