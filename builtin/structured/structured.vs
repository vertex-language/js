package structured

import (
    "js/object"
    "js/value"
)

/// Register registers JSON and structured data built-ins (§25) into the realm.
public func Register(into realm: object.Realm) {
    let g = realm.GlobalObject

    let jsonObj = realm.NewObject()
    jsonObj.InternalTag = "JSON"

    // JSON.stringify
    jsonObj.Set("stringify", value.Value.Object(realm.NewFunction(name: "stringify") { _, _, args in
        if args.isEmpty { return value.Value.Undefined }
        let val = args[0]
        return value.Value.String(stringifyValue(val))
    }))

    // JSON.parse
    jsonObj.Set("parse", value.Value.Object(realm.NewFunction(name: "parse") { r, _, args in
        if args.isEmpty { return value.Value.Undefined }
        let s = args[0].ToString()
        return parseJSON(s, realm: r)
    }))

    g.Set("JSON", value.Value.Object(jsonObj))
}

func stringifyValue(_ val: value.Value) -> string {
    switch val.Type {
    case .undefined:
        return "null"
    case .null:
        return "null"
    case .boolean:
        return val.IntVal != 0 ? "true" : "false"
    case .int32:
        return "\(val.IntVal)"
    case .number:
        if val.DoubleVal.isNaN || val.DoubleVal.isInfinite { return "null" }
        if val.DoubleVal == float64(int64(val.DoubleVal)) {
            return "\(int64(val.DoubleVal))"
        }
        return "\(val.DoubleVal)"
    case .string:
        return "\"\(escapeJSONString(val.StrVal))\""
    case .symbol:
        return "null"
    case .object:
        if let obj = val.ObjVal as? object.JSObject {
            if obj.InternalTag == "Array" {
                var pieces: [string] = []
                for el in obj.Elements {
                    pieces.append(stringifyValue(el))
                }
                return "[" + pieces.joined(separator: ",") + "]"
            }
            var pairs: [string] = []
            for key in obj.Keys {
                let v = obj.Get(key)
                if !v.IsUndefined {
                    pairs.append("\"\(escapeJSONString(key))\":" + stringifyValue(v))
                }
            }
            return "{" + pairs.joined(separator: ",") + "}"
        }
        return "{}"
    }
}

func escapeJSONString(_ s: string) -> string {
    var res = ""
    for b in [uint8](s.utf8) {
        switch b {
        case 0x0A: res += "\\n"
        case 0x0D: res += "\\r"
        case 0x09: res += "\\t"
        case 0x22: res += "\\\""
        case 0x5C: res += "\\\\"
        default: res += String(decoding: [b], as: UTF8.self)
        }
    }
    return res
}

func parseJSON(_ s: string, realm: object.Realm) -> value.Value {
    let bytes = [uint8](s.utf8)
    var i = 0

    func skipWs() {
        while i < bytes.count && (bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0A || bytes[i] == 0x0D) {
            i += 1
        }
    }

    func parseVal() -> value.Value {
        skipWs()
        if i >= bytes.count { return value.Value.Undefined }
        let b = bytes[i]

        if b == 0x22 { // '"' string
            i += 1
            var strBytes: [uint8] = []
            while i < bytes.count && bytes[i] != 0x22 {
                if bytes[i] == 0x5C && i + 1 < bytes.count {
                    i += 1
                    switch bytes[i] {
                    case 0x6E: strBytes.append(0x0A)
                    case 0x72: strBytes.append(0x0D)
                    case 0x74: strBytes.append(0x09)
                    case 0x22: strBytes.append(0x22)
                    case 0x5C: strBytes.append(0x5C)
                    default: strBytes.append(bytes[i])
                    }
                } else {
                    strBytes.append(bytes[i])
                }
                i += 1
            }
            if i < bytes.count { i += 1 }
            return value.Value.String(String(decoding: strBytes, as: UTF8.self))
        }

        if b == 0x7B { // '{' object
            i += 1
            let obj = realm.NewObject()
            skipWs()
            if i < bytes.count && bytes[i] == 0x7D {
                i += 1
                return value.Value.Object(obj)
            }
            while i < bytes.count {
                skipWs()
                let kVal = parseVal()
                skipWs()
                if i < bytes.count && bytes[i] == 0x3A { i += 1 } // ':'
                skipWs()
                let vVal = parseVal()
                obj.Set(kVal.ToString(), vVal)
                skipWs()
                if i < bytes.count && bytes[i] == 0x2C { i += 1; continue } // ','
                if i < bytes.count && bytes[i] == 0x7D { i += 1; break } // '}'
                break
            }
            return value.Value.Object(obj)
        }

        if b == 0x5B { // '[' array
            i += 1
            let arr = realm.NewArray()
            skipWs()
            if i < bytes.count && bytes[i] == 0x5D {
                i += 1
                return value.Value.Object(arr)
            }
            while i < bytes.count {
                skipWs()
                let v = parseVal()
                arr.SetElement(arr.Elements.count, v)
                skipWs()
                if i < bytes.count && bytes[i] == 0x2C { i += 1; continue }
                if i < bytes.count && bytes[i] == 0x5D { i += 1; break }
                break
            }
            return value.Value.Object(arr)
        }

        if (b >= 0x30 && b <= 0x39) || b == 0x2D { // number
            let start = i
            if b == 0x2D { i += 1 }
            while i < bytes.count && ((bytes[i] >= 0x30 && bytes[i] <= 0x39) || bytes[i] == 0x2E || bytes[i] == 0x65 || bytes[i] == 0x45 || bytes[i] == 0x2B || bytes[i] == 0x2D) {
                i += 1
            }
            var sub: [uint8] = []
            for idx in start..<i { sub.append(bytes[idx]) }
            let numStr = String(decoding: sub, as: UTF8.self)
            return value.Value.Number(float64(numStr) ?? 0.0)
        }

        if b == 0x74 && i + 3 < bytes.count { // true
            i += 4
            return value.Value.True
        }
        if b == 0x66 && i + 4 < bytes.count { // false
            i += 5
            return value.Value.False
        }
        if b == 0x6E && i + 3 < bytes.count { // null
            i += 4
            return value.Value.Null
        }

        return value.Value.Undefined
    }

    return parseVal()
}
