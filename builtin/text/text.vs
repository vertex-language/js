package text

import (
    "js/object"
    "js/value"
)

func trim(_ s: string) -> string {
    let bytes = [uint8](s.utf8)
    var start = 0
    while start < bytes.count && (bytes[start] == 0x20 || bytes[start] == 0x09 || bytes[start] == 0x0A || bytes[start] == 0x0D) {
        start += 1
    }
    var end = bytes.count
    while end > start && (bytes[end - 1] == 0x20 || bytes[end - 1] == 0x09 || bytes[end - 1] == 0x0A || bytes[end - 1] == 0x0D) {
        end -= 1
    }
    if start >= end { return "" }
    var sub: [uint8] = []
    for i in start..<end { sub.append(bytes[i]) }
    return String(decoding: sub, as: UTF8.self)
}

/// Register registers String built-in (§22) into the realm.
public func Register(into realm: object.Realm) {
    let g = realm.GlobalObject

    let stringPrototype = realm.NewObject()
    stringPrototype.InternalTag = "String"

    // String constructor
    let stringCtor = realm.NewFunction(name: "String") { _, _, args in
        let s = args.isEmpty ? "" : args[0].ToString()
        return value.Value.String(s)
    }
    stringCtor.Set("prototype", value.Value.Object(stringPrototype))

    // String.fromCharCode
    let fromCharCodeFn = realm.NewFunction(name: "fromCharCode") { _, _, args in
        var u16: [uint16] = []
        for a in args {
            u16.append(uint16(a.ToUint32() & 0xFFFF))
        }
        var utf8: [uint8] = []
        for u in u16 {
            if u <= 0x7F {
                utf8.append(uint8(u))
            } else if u <= 0x7FF {
                utf8.append(uint8(0xC0 | (u >> 6)))
                utf8.append(uint8(0x80 | (u & 0x3F)))
            } else {
                utf8.append(uint8(0xE0 | (u >> 12)))
                utf8.append(uint8(0x80 | ((u >> 6) & 0x3F)))
                utf8.append(uint8(0x80 | (u & 0x3F)))
            }
        }
        return value.Value.String(String(decoding: utf8, as: UTF8.self))
    }
    stringCtor.Set("fromCharCode", value.Value.Object(fromCharCodeFn))

    // charAt
    stringPrototype.Set("charAt", value.Value.Object(realm.NewFunction(name: "charAt") { _, thisVal, args in
        let s = thisVal.ToString()
        let pos = args.isEmpty ? 0 : Int(args[0].ToInt32())
        let chars = Array(s)
        if pos >= 0 && pos < chars.count {
            return value.Value.String(String(chars[pos]))
        }
        return value.Value.String("")
    }))

    // charCodeAt
    stringPrototype.Set("charCodeAt", value.Value.Object(realm.NewFunction(name: "charCodeAt") { _, thisVal, args in
        let s = thisVal.ToString()
        let pos = args.isEmpty ? 0 : Int(args[0].ToInt32())
        var u16: [uint16] = []
        for sc in s.unicodeScalars {
            let v = sc.value
            if v < 0x10000 {
                u16.append(uint16(v))
            } else {
                let shifted = v - 0x10000
                u16.append(uint16(0xD800 + (shifted >> 10)))
                u16.append(uint16(0xDC00 + (shifted & 0x3FF)))
            }
        }
        if pos >= 0 && pos < u16.count {
            return value.Value.Int(int32(u16[pos]))
        }
        return value.Value.Number(float64.nan)
    }))

    // concat
    stringPrototype.Set("concat", value.Value.Object(realm.NewFunction(name: "concat") { _, thisVal, args in
        var res = thisVal.ToString()
        for a in args {
            res += a.ToString()
        }
        return value.Value.String(res)
    }))

    // indexOf
    stringPrototype.Set("indexOf", value.Value.Object(realm.NewFunction(name: "indexOf") { _, thisVal, args in
        let s = thisVal.ToString()
        let searchStr = args.isEmpty ? "undefined" : args[0].ToString()
        var pos = 0
        if args.count > 1 {
            pos = Int(args[1].ToInt32())
            if pos < 0 { pos = 0 }
        }
        let sBytes = [uint8](s.utf8)
        let needleBytes = [uint8](searchStr.utf8)
        if needleBytes.isEmpty {
            return value.Value.Int(int32(pos <= sBytes.count ? pos : sBytes.count))
        }
        if sBytes.count < needleBytes.count + pos {
            return value.Value.Int(-1)
        }
        for i in pos...(sBytes.count - needleBytes.count) {
            var match = true
            for j in 0..<needleBytes.count {
                if sBytes[i + j] != needleBytes[j] {
                    match = false
                    break
                }
            }
            if match {
                return value.Value.Int(int32(i))
            }
        }
        return value.Value.Int(-1)
    }))

    // slice
    stringPrototype.Set("slice", value.Value.Object(realm.NewFunction(name: "slice") { _, thisVal, args in
        let s = thisVal.ToString()
        let len = s.count
        var start = args.isEmpty ? 0 : Int(args[0].ToInt32())
        if start < 0 { start = len + start; if start < 0 { start = 0 } }
        else if start > len { start = len }

        var end = len
        if args.count > 1 && !args[1].IsUndefined {
            end = Int(args[1].ToInt32())
            if end < 0 { end = len + end; if end < 0 { end = 0 } }
            else if end > len { end = len }
        }
        if start >= end { return value.Value.String("") }
        let chars = Array(s)
        var sub = ""
        for i in start..<end {
            sub += String(chars[i])
        }
        return value.Value.String(sub)
    }))

    // trim
    stringPrototype.Set("trim", value.Value.Object(realm.NewFunction(name: "trim") { _, thisVal, _ in
        return value.Value.String(trim(thisVal.ToString()))
    }))

    // toLowerCase
    stringPrototype.Set("toLowerCase", value.Value.Object(realm.NewFunction(name: "toLowerCase") { _, thisVal, _ in
        return value.Value.String(thisVal.ToString().lowercased())
    }))

    // toUpperCase
    stringPrototype.Set("toUpperCase", value.Value.Object(realm.NewFunction(name: "toUpperCase") { _, thisVal, _ in
        return value.Value.String(thisVal.ToString().uppercased())
    }))

    // repeat
    stringPrototype.Set("repeat", value.Value.Object(realm.NewFunction(name: "repeat") { _, thisVal, args in
        let s = thisVal.ToString()
        let count = args.isEmpty ? 0 : Int(args[0].ToInt32())
        if count < 0 { return value.Value.Undefined }
        var res = ""
        for _ in 0..<count {
            res += s
        }
        return value.Value.String(res)
    }))

    g.Set("String", value.Value.Object(stringCtor))
}
