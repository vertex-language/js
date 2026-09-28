package global

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

func hasPrefix(_ s: string, _ prefix: string) -> bool {
    let sb = [uint8](s.utf8)
    let pb = [uint8](prefix.utf8)
    if sb.count < pb.count { return false }
    for i in 0..<pb.count {
        if sb[i] != pb[i] { return false }
    }
    return true
}

func parseIntegerWithRadix(_ str: string, radix: int) -> int64? {
    let bytes = [uint8](str.utf8)
    if bytes.isEmpty { return nil }
    var start = 0
    var sign: int64 = 1
    if bytes[0] == 0x2D { // '-'
        sign = -1
        start = 1
    } else if bytes[0] == 0x2B { // '+'
        start = 1
    }
    if start >= bytes.count { return nil }
    var result: int64 = 0
    var hasDigits = false
    let r = int64(radix)
    for idx in start..<bytes.count {
        let b = bytes[idx]
        var digit: int64 = -1
        if b >= 0x30 && b <= 0x39 {
            digit = int64(b - 0x30)
        } else if b >= 0x61 && b <= 0x7A {
            digit = int64(b - 0x61 + 10)
        } else if b >= 0x41 && b <= 0x5A {
            digit = int64(b - 0x41 + 10)
        }
        if digit < 0 || digit >= r {
            break
        }
        hasDigits = true
        result = result * r + digit
    }
    if !hasDigits { return nil }
    return result * sign
}

/// Register registers Global Object functions (§19) into the realm.
public func Register(into realm: object.Realm) {
    let g = realm.GlobalObject

    // isNaN
    let isNaNFn = realm.NewFunction(name: "isNaN") { _, _, args in
        let num = args.isEmpty ? float64.nan : args[0].ToNumber()
        return value.Value.Boolean(num.isNaN)
    }
    g.Set("isNaN", value.Value.Object(isNaNFn))

    // isFinite
    let isFiniteFn = realm.NewFunction(name: "isFinite") { _, _, args in
        let num = args.isEmpty ? float64.nan : args[0].ToNumber()
        return value.Value.Boolean(!num.isNaN && !num.isInfinite)
    }
    g.Set("isFinite", value.Value.Object(isFiniteFn))

    // parseInt
    let parseIntFn = realm.NewFunction(name: "parseInt") { _, _, args in
        if args.isEmpty { return value.Value.Number(float64.nan) }
        var str = trim(args[0].ToString())
        if str.isEmpty { return value.Value.Number(float64.nan) }
        var radix = 10
        if args.count > 1 && !args[1].IsUndefined {
            let r = Int(args[1].ToInt32())
            if r >= 2 && r <= 36 { radix = r }
        }
        if hasPrefix(str, "0x") || hasPrefix(str, "0X") {
            radix = 16
            let chars = Array(str)
            var rest = ""
            for idx in 2..<chars.count { rest += String(chars[idx]) }
            str = rest
        }
        if let val = parseIntegerWithRadix(str, radix: radix) {
            return value.Value.Number(float64(val))
        }
        return value.Value.Number(float64.nan)
    }
    g.Set("parseInt", value.Value.Object(parseIntFn))

    // parseFloat
    let parseFloatFn = realm.NewFunction(name: "parseFloat") { _, _, args in
        if args.isEmpty { return value.Value.Number(float64.nan) }
        let str = trim(args[0].ToString())
        if let d = float64(str) {
            return value.Value.Number(d)
        }
        return value.Value.Number(float64.nan)
    }
    g.Set("parseFloat", value.Value.Object(parseFloatFn))

    // gc()
    let gcFn = realm.NewFunction(name: "gc") { r, _, _ in
        r.Heap.Collect()
        return value.Value.Undefined
    }
    g.Set("gc", value.Value.Object(gcFn))
}
