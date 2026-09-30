// Package global installs the global object's own functions and values
// (ECMA-262 §19): NaN, Infinity, undefined, eval, isNaN, isFinite,
// parseInt, parseFloat, the URI functions, and Annex B's escape/unescape.
package global

import (
    "js/object"
    "js/str"
    "js/value"
    "unicode/utf16"
    "unicode/utf8"
)

typealias Value = object.Value

/// Install defines the global functions and value properties.
public func Install(_ r: object.Realm) {
    let g = r.Global
    g.DefineData(value.PropertyKey.Named("NaN"), .number(float64.nan), writable: false, enumerable: false, configurable: false)
    g.DefineData(value.PropertyKey.Named("Infinity"), .number(float64.infinity), writable: false, enumerable: false, configurable: false)
    g.DefineData(value.PropertyKey.Named("undefined"), .undefined, writable: false, enumerable: false, configurable: false)

    let ev = r.Function("eval", 1) { _, args, _ in
        guard case .string(let s) = object.Arg(args, 0) else { return object.Arg(args, 0) }
        return try r.Engine!.IndirectEval(r, s)
    }
    r.EvalFunction = ev
    r.DefineGlobal("eval", .object(ev))

    r.Method(g, "isNaN", 1) { _, args, _ in
        return .bool(try object.ToNumber(object.Arg(args, 0)).isNaN)
    }
    r.Method(g, "isFinite", 1) { _, args, _ in
        return .bool(try object.ToNumber(object.Arg(args, 0)).isFinite)
    }
    let parseFloat = r.Function("parseFloat", 1) { _, args, _ in
        return .number(value.ParseFloat(try object.ToString(object.Arg(args, 0))))
    }
    let parseInt = r.Function("parseInt", 2) { _, args, _ in
        let s = try object.ToString(object.Arg(args, 0))
        let radix = try object.ToInt32(object.Arg(args, 1))
        return .number(value.ParseInt(s, int(radix)))
    }
    r.DefineGlobal("parseFloat", .object(parseFloat))
    r.DefineGlobal("parseInt", .object(parseInt))
    r.Intrinsics["parseFloat"] = parseFloat
    r.Intrinsics["parseInt"] = parseInt

    r.Method(g, "encodeURI", 1) { _, args, _ in
        return .string(try Encode(try object.ToString(object.Arg(args, 0)), extraUnescaped: ";/?:@&=+$,#"))
    }
    r.Method(g, "encodeURIComponent", 1) { _, args, _ in
        return .string(try Encode(try object.ToString(object.Arg(args, 0)), extraUnescaped: ""))
    }
    r.Method(g, "decodeURI", 1) { _, args, _ in
        return .string(try Decode(try object.ToString(object.Arg(args, 0)), preserve: ";/?:@&=+$,#"))
    }
    r.Method(g, "decodeURIComponent", 1) { _, args, _ in
        return .string(try Decode(try object.ToString(object.Arg(args, 0)), preserve: ""))
    }
    r.Method(g, "escape", 1) { _, args, _ in
        return .string(Escape(try object.ToString(object.Arg(args, 0))))
    }
    r.Method(g, "unescape", 1) { _, args, _ in
        return .string(Unescape(try object.ToString(object.Arg(args, 0))))
    }
}

// MARK: URI (§19.2.6)

let hexDigits: [uint16] = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70]

/// isURIUnreserved is uriAlpha, DecimalDigit and uriMark.
func isURIUnreserved(_ c: uint16) -> bool {
    if c >= 97 && c <= 122 { return true }
    if c >= 65 && c <= 90 { return true }
    if c >= 48 && c <= 57 { return true }
    switch c {
    case 45, 95, 46, 33, 126, 42, 39, 40, 41: return true // - _ . ! ~ * ' ( )
    default: return false
    }
}

func contains(_ set: string, _ c: uint16) -> bool {
    if c >= 128 { return false }
    for b in set.utf8 where uint16(b) == c { return true }
    return false
}

/// Encode is Encode (§19.2.6.5).
public func Encode(_ s: str.JSString, extraUnescaped: string) throws -> str.JSString {
    let u = s.Units
    var out = str.Builder()
    var k = 0
    while k < u.count {
        let c = u[k]
        if isURIUnreserved(c) || contains(extraUnescaped, c) {
            out.AppendUnit(c)
            k += 1
            continue
        }
        let (cp, width) = utf16.DecodeAt(u, k)
        if cp >= 0xD800 && cp <= 0xDFFF {
            throw object.ThrowURIError("URI malformed")
        }
        k += width
        var bytes: [uint8] = []
        utf8.Append(&bytes, cp)
        for b in bytes {
            out.AppendUnit(37)
            out.AppendUnit(hexDigits[int(b >> 4)])
            out.AppendUnit(hexDigits[int(b & 15)])
        }
    }
    return out.Build()
}

func hexValue(_ c: uint16) -> int {
    if c >= 48 && c <= 57 { return int(c) - 48 }
    if c >= 65 && c <= 70 { return int(c) - 55 }
    if c >= 97 && c <= 102 { return int(c) - 87 }
    return -1
}

func hexByte(_ u: [uint16], _ at: int) -> int {
    if at + 2 >= u.count { return -1 }
    if u[at] != 37 { return -1 }
    let hi = hexValue(u[at + 1])
    let lo = hexValue(u[at + 2])
    if hi < 0 || lo < 0 { return -1 }
    return hi * 16 + lo
}

/// Decode is Decode (§19.2.6.6).
public func Decode(_ s: str.JSString, preserve: string) throws -> str.JSString {
    let u = s.Units
    var out = str.Builder()
    var k = 0
    while k < u.count {
        let c = u[k]
        if c != 37 {
            out.AppendUnit(c)
            k += 1
            continue
        }
        let start = k
        let b = hexByte(u, k)
        if b < 0 { throw object.ThrowURIError("URI malformed") }
        k += 3
        if b < 0x80 {
            if contains(preserve, uint16(b)) {
                var i = start
                while i < k { out.AppendUnit(u[i]); i += 1 }
            } else {
                out.AppendUnit(uint16(b))
            }
            continue
        }
        var n = 0
        if b & 0xE0 == 0xC0 { n = 2 } else if b & 0xF0 == 0xE0 { n = 3 } else if b & 0xF8 == 0xF0 { n = 4 }
        if n == 0 { throw object.ThrowURIError("URI malformed") }
        var bytes: [uint8] = [uint8(b)]
        var j = 1
        while j < n {
            let nb = hexByte(u, k)
            if nb < 0 || nb & 0xC0 != 0x80 { throw object.ThrowURIError("URI malformed") }
            bytes.append(uint8(nb))
            k += 3
            j += 1
        }
        let (cp, width) = utf8.DecodeAt(bytes, 0)
        if width != n {
            throw object.ThrowURIError("URI malformed")
        }
        out.AppendCodePoint(cp)
    }
    return out.Build()
}

// MARK: Annex B (§B.2.1)

/// Escape is escape(string).
public func Escape(_ s: str.JSString) -> str.JSString {
    var out = str.Builder()
    for c in s.Units {
        let plain = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || contains("@*_+-./", c)
        if plain {
            out.AppendUnit(c)
        } else if c < 256 {
            out.AppendUnit(37)
            out.AppendUnit(hexDigits[int(c >> 4)])
            out.AppendUnit(hexDigits[int(c & 15)])
        } else {
            out.AppendUnit(37)
            out.AppendUnit(117)
            out.AppendUnit(hexDigits[int(c >> 12)])
            out.AppendUnit(hexDigits[int((c >> 8) & 15)])
            out.AppendUnit(hexDigits[int((c >> 4) & 15)])
            out.AppendUnit(hexDigits[int(c & 15)])
        }
    }
    return out.Build()
}

/// Unescape is unescape(string).
public func Unescape(_ s: str.JSString) -> str.JSString {
    let u = s.Units
    var out = str.Builder()
    var k = 0
    while k < u.count {
        let c = u[k]
        if c == 37 {
            if k + 6 <= u.count && u[k + 1] == 117 {
                let a = hexValue(u[k + 2]), b = hexValue(u[k + 3]), cc = hexValue(u[k + 4]), d = hexValue(u[k + 5])
                if a >= 0 && b >= 0 && cc >= 0 && d >= 0 {
                    out.AppendUnit(uint16(a << 12 | b << 8 | cc << 4 | d))
                    k += 6
                    continue
                }
            }
            if k + 3 <= u.count {
                let a = hexValue(u[k + 1]), b = hexValue(u[k + 2])
                if a >= 0 && b >= 0 {
                    out.AppendUnit(uint16(a << 4 | b))
                    k += 3
                    continue
                }
            }
        }
        out.AppendUnit(c)
        k += 1
    }
    return out.Build()
}
