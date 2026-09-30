package value

import (
    "math/big"
    "js/str"
    "js/token"
)

// MARK: Number::toString (§6.1.6.1.20)

/// shortestDigits splits a finite, positive double into its shortest
/// round-tripping decimal digits and the exponent n, so that the value is
/// 0.d1d2...dk × 10^n. It reads the digits from the runtime's shortest
/// formatter, which prints forms like 123.0, 0.30000000000000004, 1e-07
/// and 1.2345e+21.
func shortestDigits(_ d: float64) -> (digits: [uint8], n: int) {
    let text = "\(d)"
    var digits: [uint8] = []
    var pointAt = -1
    var exp = 0
    var inExp = false
    var expNeg = false
    for c in text.utf8 {
        if inExp {
            if c == 0x2D { expNeg = true } else if c >= 0x30 && c <= 0x39 { exp = exp * 10 + int(c - 0x30) }
        } else if c == 0x65 || c == 0x45 {
            inExp = true
        } else if c == 0x2E {
            pointAt = digits.count
        } else if c >= 0x30 && c <= 0x39 {
            digits.append(c)
        }
    }
    if expNeg { exp = -exp }
    if pointAt < 0 { pointAt = digits.count }
    // Drop leading zeros, moving the point.
    var lead = 0
    while lead < digits.count - 1 && digits[lead] == 0x30 { lead += 1 }
    var trimmed: [uint8] = []
    var i = lead
    while i < digits.count { trimmed.append(digits[i]); i += 1 }
    var n = pointAt - lead + exp
    // Drop trailing zeros.
    while trimmed.count > 1 && trimmed[trimmed.count - 1] == 0x30 { _ = trimmed.removeLast() }
    if trimmed.count == 1 && trimmed[0] == 0x30 { n = 1 }
    return (trimmed, n)
}

/// NumberToString is Number::toString(x) in radix 10.
public func NumberToString(_ x: float64) -> string {
    if x.isNaN { return "NaN" }
    if x == 0 { return "0" }
    if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
    if x < 0 { return "-" + NumberToString(-x) }
    if x < 1e21 && x == x.rounded(.towardZero) && x < 9007199254740992 {
        return "\(int64(x))"
    }
    let (digits, n) = shortestDigits(x)
    let k = digits.count
    var out: [uint8] = []
    if k <= n && n <= 21 {
        out.append(contentsOf: digits)
        var z = 0
        while z < n - k { out.append(0x30); z += 1 }
    } else if 0 < n && n <= 21 {
        var i = 0
        while i < n { out.append(digits[i]); i += 1 }
        out.append(0x2E)
        while i < k { out.append(digits[i]); i += 1 }
    } else if -6 < n && n <= 0 {
        out.append(0x30)
        out.append(0x2E)
        var z = 0
        while z < -n { out.append(0x30); z += 1 }
        out.append(contentsOf: digits)
    } else {
        out.append(digits[0])
        if k > 1 {
            out.append(0x2E)
            var i = 1
            while i < k { out.append(digits[i]); i += 1 }
        }
        out.append(0x65)
        let e = n - 1
        out.append(e < 0 ? 0x2D : 0x2B)
        out.append(contentsOf: [uint8]("\(e < 0 ? -e : e)".utf8))
    }
    return string(decoding: out, as: UTF8.self)
}

/// NumberToJSString is NumberToString as a JSString.
public func NumberToJSString(_ x: float64) -> str.JSString {
    if x >= 0 && x < 10 && x == x.rounded(.towardZero) {
        return smallInts[int(x)]
    }
    return str.JSString.From(NumberToString(x))
}

let smallInts: [str.JSString] = [str.Name("0"), str.Name("1"), str.Name("2"), str.Name("3"), str.Name("4"), str.Name("5"), str.Name("6"), str.Name("7"), str.Name("8"), str.Name("9")]

/// NumberToRadixString is Number.prototype.toString(radix) for radix != 10,
/// after V8's DoubleToRadixCString.
public func NumberToRadixString(_ value: float64, _ radix: int) -> string {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
    if value == 0 { return "0" }
    let chars: [uint8] = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122]
    let neg = value < 0
    let v = neg ? -value : value
    var integer = v.rounded(.down)
    var fraction = v - integer
    // The precision to which fraction digits are exact: half the distance
    // to the next double.
    var delta = 0.5 * (nextUp(v) - v)
    let minDelta = nextUp(0.0)
    if minDelta > delta { delta = minDelta }
    var fracDigits: [uint8] = []
    if fraction >= delta {
        while true {
            fraction *= float64(radix)
            delta *= float64(radix)
            let digit = int(fraction)
            fracDigits.append(chars[digit])
            fraction -= float64(digit)
            if fraction > 0.5 || (fraction == 0.5 && (digit & 1) == 1) {
                if fraction + delta > 1 {
                    // Round up, propagating the carry.
                    while true {
                        if fracDigits.isEmpty {
                            integer += 1
                            break
                        }
                        let last = fracDigits.removeLast()
                        var dv = int(last) - 48
                        if dv > 9 { dv = int(last) - 97 + 10 }
                        if dv + 1 < radix {
                            fracDigits.append(chars[dv + 1])
                            break
                        }
                    }
                    break
                }
            }
            if !(fraction >= delta) { break }
        }
    }
    // Integer part: exact digits while the value is exactly representable.
    var intDigits: [uint8] = []
    let bits = integer.bitPattern
    let exponent = int((bits >> 52) & 0x7FF) - 1075
    if exponent > 0 {
        // Beyond 2^53: use exact big integer division.
        let big = BigInt.FromDouble(integer)
        let s = big.ToString(radix)
        intDigits = [uint8](s.utf8)
    } else {
        var ip = integer
        if ip == 0 { intDigits.append(48) }
        while ip >= 1 {
            let r = ip.truncatingRemainder(dividingBy: float64(radix))
            intDigits.append(chars[int(r)])
            ip = (ip - r) / float64(radix)
        }
        var lo = 0
        var hi = intDigits.count - 1
        while lo < hi {
            let t = intDigits[lo]
            intDigits[lo] = intDigits[hi]
            intDigits[hi] = t
            lo += 1
            hi -= 1
        }
    }
    var out: [uint8] = []
    if neg { out.append(0x2D) }
    out.append(contentsOf: intDigits)
    if !fracDigits.isEmpty {
        out.append(0x2E)
        out.append(contentsOf: fracDigits)
    }
    return string(decoding: out, as: UTF8.self)
}

func nextUp(_ d: float64) -> float64 {
    if d.isNaN || (d.isInfinite && d > 0) { return d }
    if d == 0 { return float64(bitPattern: 1) }
    let b = d.bitPattern
    if d > 0 { return float64(bitPattern: b + 1) }
    return float64(bitPattern: b - 1)
}

// MARK: exact decimal expansion, for toFixed, toExponential and toPrecision

/// exactDecimal expands a finite, positive double exactly: digits with no
/// leading zeros, and the position of the decimal point within them
/// (value = 0.digits × 10^point).
func exactDecimal(_ d: float64) -> (digits: [uint8], point: int) {
    let bits = d.bitPattern
    let exp = int((bits >> 52) & 0x7FF)
    var mant = bits & 0xFFFFFFFFFFFFF
    var e2: int
    if exp == 0 {
        e2 = -1074
    } else {
        mant |= uint64(1) << 52
        e2 = exp - 1075
    }
    var n = big.Nat.FromU64(mant)
    var scale = 0 // value = n × 10^scale
    if e2 >= 0 {
        n = big.ShiftLeft(n, e2)
    } else {
        // m / 2^k = m × 5^k / 10^k
        n = big.Mul(n, big.Pow(big.Nat.FromU32(5), -e2))
        scale = e2
    }
    let s = n.ToString(10)
    var digits = [uint8](s.utf8)
    let point = digits.count + scale
    while digits.count > 1 && digits[digits.count - 1] == 0x30 { _ = digits.removeLast() }
    return (digits, point)
}

/// roundDigits rounds a digit string to keep `keep` digits, half up (the
/// spec picks the larger n on a tie). It returns the new digits and
/// whether a carry grew the number by a digit.
func roundDigits(_ digits: [uint8], _ keep: int) -> (digits: [uint8], carried: bool) {
    if keep < 0 { return ([], false) }
    if keep >= digits.count {
        var out = digits
        while out.count < keep { out.append(0x30) }
        return (out, false)
    }
    var out: [uint8] = []
    var i = 0
    while i < keep { out.append(digits[i]); i += 1 }
    if digits[keep] >= 0x35 {
        var j = out.count - 1
        while j >= 0 {
            if out[j] == 0x39 {
                out[j] = 0x30
                j -= 1
            } else {
                out[j] += 1
                break
            }
        }
        if j < 0 {
            out.insert(0x31, at: 0)
            return (out, true)
        }
    }
    return (out, false)
}

/// ToFixed is Number.prototype.toFixed for 0 <= f <= 100, x finite and
/// below 1e21 in magnitude.
public func ToFixed(_ x: float64, _ f: int) -> string {
    var neg = x < 0
    let v = neg ? -x : x
    var out: [uint8] = []
    if v == 0 {
        neg = false
        out.append(0x30)
        if f > 0 {
            out.append(0x2E)
            var i = 0
            while i < f { out.append(0x30); i += 1 }
        }
        return string(decoding: out, as: UTF8.self)
    }
    let (digits, point) = exactDecimal(v)
    // Digits of n = round(v × 10^f): the integer part has point + f digits.
    let keep = point + f
    var nd: [uint8] = []
    if keep < 0 {
        nd = [0x30]
    } else if keep == 0 {
        nd = digits[0] >= 0x35 ? [0x31] : [0x30]
    } else {
        let (r, _) = roundDigits(digits, keep)
        nd = r
    }
    // Drop leading zeros but keep at least f + 1 digits.
    while nd.count < f + 1 { nd.insert(0x30, at: 0) }
    var start = 0
    while start < nd.count - f - 1 && nd[start] == 0x30 { start += 1 }
    var trimmed: [uint8] = []
    var i = start
    while i < nd.count { trimmed.append(nd[i]); i += 1 }
    let intLen = trimmed.count - f
    if neg { out.append(0x2D) }
    i = 0
    while i < intLen { out.append(trimmed[i]); i += 1 }
    if f > 0 {
        out.append(0x2E)
        while i < trimmed.count { out.append(trimmed[i]); i += 1 }
    }
    return string(decoding: out, as: UTF8.self)
}

/// ToExponential is Number.prototype.toExponential; f < 0 means as many
/// digits as needed (the shortest form).
public func ToExponential(_ x: float64, _ f: int) -> string {
    let neg = x < 0
    let v = neg ? -x : x
    var digits: [uint8]
    var e: int
    if v == 0 {
        digits = [0x30]
        var i = 0
        while i < (f < 0 ? 0 : f) { digits.append(0x30); i += 1 }
        e = 0
    } else if f < 0 {
        let (d, n) = shortestDigits(v)
        digits = d
        e = n - 1
    } else {
        let (d, point) = exactDecimal(v)
        let (r, carried) = roundDigits(d, f + 1)
        digits = r
        e = point - 1 + (carried ? 1 : 0)
        if carried { _ = digits.removeLast() }
    }
    var out: [uint8] = []
    if neg { out.append(0x2D) }
    out.append(digits[0])
    if digits.count > 1 {
        out.append(0x2E)
        var i = 1
        while i < digits.count { out.append(digits[i]); i += 1 }
    }
    out.append(0x65)
    out.append(e < 0 ? 0x2D : 0x2B)
    out.append(contentsOf: [uint8]("\(e < 0 ? -e : e)".utf8))
    return string(decoding: out, as: UTF8.self)
}

/// ToPrecision is Number.prototype.toPrecision for 1 <= p <= 100.
public func ToPrecision(_ x: float64, _ p: int) -> string {
    let neg = x < 0
    let v = neg ? -x : x
    var digits: [uint8]
    var e: int
    if v == 0 {
        digits = []
        var i = 0
        while i < p { digits.append(0x30); i += 1 }
        e = 0
    } else {
        let (d, point) = exactDecimal(v)
        let (r, carried) = roundDigits(d, p)
        digits = r
        e = point - 1 + (carried ? 1 : 0)
        if carried { _ = digits.removeLast() }
    }
    var out: [uint8] = []
    if neg { out.append(0x2D) }
    if e < -6 || e >= p {
        out.append(digits[0])
        if p > 1 {
            out.append(0x2E)
            var i = 1
            while i < digits.count { out.append(digits[i]); i += 1 }
        }
        out.append(0x65)
        out.append(e < 0 ? 0x2D : 0x2B)
        out.append(contentsOf: [uint8]("\(e < 0 ? -e : e)".utf8))
    } else if e == p - 1 {
        out.append(contentsOf: digits)
    } else if e >= 0 {
        var i = 0
        while i <= e { out.append(digits[i]); i += 1 }
        out.append(0x2E)
        while i < digits.count { out.append(digits[i]); i += 1 }
    } else {
        out.append(0x30)
        out.append(0x2E)
        var z = 0
        while z < -(e + 1) { out.append(0x30); z += 1 }
        out.append(contentsOf: digits)
    }
    return string(decoding: out, as: UTF8.self)
}

// MARK: StringToNumber (§7.1.4.1.1)

/// TrimSpace removes leading and trailing WhiteSpace and line terminators.
public func TrimSpace(_ u: [uint16]) -> [uint16] {
    var a = 0
    var b = u.count
    while a < b && token.IsSpace(uint32(u[a])) { a += 1 }
    while b > a && token.IsSpace(uint32(u[b - 1])) { b -= 1 }
    if a == 0 && b == u.count { return u }
    var out: [uint16] = []
    var i = a
    while i < b { out.append(u[i]); i += 1 }
    return out
}

/// StringToNumber converts a string by the StringNumericLiteral grammar:
/// NaN if it doesn't match.
public func StringToNumber(_ s: str.JSString) -> float64 {
    let u = TrimSpace(s.Units)
    if u.isEmpty { return 0 }
    var bytes: [uint8] = []
    for c in u {
        if c >= 0x80 { return float64.nan }
        bytes.append(uint8(c))
    }
    return parseNumericLiteral(bytes)
}

func parseNumericLiteral(_ b: [uint8]) -> float64 {
    let n = b.count
    // 0x, 0o, 0b: no sign allowed.
    if n > 2 && b[0] == 0x30 {
        let c = b[1] | 0x20
        var radix = 0
        if c == 0x78 { radix = 16 } else if c == 0x6F { radix = 8 } else if c == 0x62 { radix = 2 }
        if radix != 0 {
            var v: float64 = 0
            var i = 2
            var digits: [uint8] = []
            while i < n {
                let h = token.HexValue(uint32(b[i]))
                if h < 0 || h >= radix { return float64.nan }
                v = v * float64(radix) + float64(h)
                digits.append(b[i])
                i += 1
            }
            if v >= 9007199254740992 {
                // Past 2^53 the running sum rounds; convert exactly instead.
                return big.Nat.Parse(string(decoding: digits, as: UTF8.self), radix: radix)!.ToFloat64()
            }
            return v
        }
    }
    var i = 0
    var neg = false
    if i < n && (b[i] == 0x2B || b[i] == 0x2D) {
        neg = b[i] == 0x2D
        i += 1
    }
    // Infinity
    let inf: [uint8] = [73, 110, 102, 105, 110, 105, 116, 121]
    if n - i == 8 {
        var match = true
        var j = 0
        while j < 8 { if b[i + j] != inf[j] { match = false; break }; j += 1 }
        if match { return neg ? -float64.infinity : float64.infinity }
    }
    // Validate StrDecimalLiteral: digits [. digits] [e [+-] digits], with
    // at least one digit in the mantissa.
    let start = i
    var mantDigits = 0
    while i < n && b[i] >= 0x30 && b[i] <= 0x39 { i += 1; mantDigits += 1 }
    if i < n && b[i] == 0x2E {
        i += 1
        while i < n && b[i] >= 0x30 && b[i] <= 0x39 { i += 1; mantDigits += 1 }
    }
    if mantDigits == 0 { return float64.nan }
    if i < n && (b[i] | 0x20) == 0x65 {
        i += 1
        if i < n && (b[i] == 0x2B || b[i] == 0x2D) { i += 1 }
        var ed = 0
        while i < n && b[i] >= 0x30 && b[i] <= 0x39 { i += 1; ed += 1 }
        if ed == 0 { return float64.nan }
    }
    if i != n { return float64.nan }
    var body: [uint8] = []
    var j = start
    while j < n { body.append(b[j]); j += 1 }
    let v = float64(string(decoding: body, as: UTF8.self)) ?? float64.nan
    return neg ? -v : v
}

/// ParseFloat is the global parseFloat: the longest prefix that is a
/// StrDecimalLiteral.
public func ParseFloat(_ s: str.JSString) -> float64 {
    let u = TrimSpace(s.Units)
    var b: [uint8] = []
    for c in u {
        if c >= 0x80 { break }
        b.append(uint8(c))
    }
    let n = b.count
    var i = 0
    var neg = false
    if i < n && (b[i] == 0x2B || b[i] == 0x2D) {
        neg = b[i] == 0x2D
        i += 1
    }
    let inf: [uint8] = [73, 110, 102, 105, 110, 105, 116, 121]
    if n - i >= 8 {
        var match = true
        var j = 0
        while j < 8 { if b[i + j] != inf[j] { match = false; break }; j += 1 }
        if match { return neg ? -float64.infinity : float64.infinity }
    }
    let start = i
    var digits = 0
    while i < n && b[i] >= 0x30 && b[i] <= 0x39 { i += 1; digits += 1 }
    if i < n && b[i] == 0x2E {
        let save = i
        i += 1
        var frac = 0
        while i < n && b[i] >= 0x30 && b[i] <= 0x39 { i += 1; frac += 1 }
        if frac == 0 && digits == 0 { i = save }
        digits += frac
    }
    if digits == 0 { return float64.nan }
    if i < n && (b[i] | 0x20) == 0x65 {
        let save = i
        i += 1
        if i < n && (b[i] == 0x2B || b[i] == 0x2D) { i += 1 }
        var ed = 0
        while i < n && b[i] >= 0x30 && b[i] <= 0x39 { i += 1; ed += 1 }
        if ed == 0 { i = save }
    }
    var body: [uint8] = []
    var j = start
    while j < i { body.append(b[j]); j += 1 }
    // "5." is valid for parseFloat; strtod accepts it too.
    let v = float64(string(decoding: body, as: UTF8.self)) ?? float64.nan
    return neg ? -v : v
}

/// ParseInt is the global parseInt.
public func ParseInt(_ s: str.JSString, _ radixIn: int) -> float64 {
    let u = TrimSpace(s.Units)
    var i = 0
    var neg = false
    if i < u.count && (u[i] == 0x2B || u[i] == 0x2D) {
        neg = u[i] == 0x2D
        i += 1
    }
    var radix = radixIn
    var stripPrefix = true
    if radix != 0 {
        if radix < 2 || radix > 36 { return float64.nan }
        if radix != 16 { stripPrefix = false }
    } else {
        radix = 10
    }
    if stripPrefix && i + 1 < u.count && u[i] == 0x30 && (u[i + 1] | 0x20) == 0x78 {
        i += 2
        radix = 16
    }
    let start = i
    var v: float64 = 0
    var digits: [uint8] = []
    while i < u.count {
        let d = token.HexValue(uint32(u[i]))
        var dv = d
        if d < 0 {
            let c = uint32(u[i]) | 0x20
            if c >= 0x67 && c <= 0x7A { dv = int(c - 0x61) + 10 } else { break }
        }
        if dv >= radix { break }
        v = v * float64(radix) + float64(dv)
        digits.append(uint8(u[i]))
        i += 1
    }
    if i == start { return float64.nan }
    if radix == 10 {
        var b: [uint8] = []
        var j = start
        while j < i { b.append(uint8(u[j])); j += 1 }
        v = float64(string(decoding: b, as: UTF8.self)) ?? v
    } else if v >= 9007199254740992 && (radix & (radix - 1)) == 0 {
        // A power-of-two radix converts exactly, as V8 does.
        v = big.Nat.Parse(string(decoding: digits, as: UTF8.self), radix: radix)!.ToFloat64()
    }
    return neg ? -v : v
}

// MARK: integer conversions (§7.1.6–§7.1.11)

/// ToInt32 wraps a double modulo 2^32 into the signed range.
public func DoubleToInt32(_ d: float64) -> int32 {
    if d.isNaN || d.isInfinite { return 0 }
    if d >= -2147483648.0 && d <= 2147483647.0 {
        return int32(d)
    }
    let t = d.rounded(.towardZero)
    var m = t.truncatingRemainder(dividingBy: 4294967296.0)
    if m < 0 { m += 4294967296.0 }
    let u = uint32(m)
    return int32(bitPattern: u)
}

public func DoubleToUint32(_ d: float64) -> uint32 {
    return uint32(bitPattern: DoubleToInt32(d))
}

/// ToIntegerOrInfinity (§7.1.5).
public func ToIntegerOrInfinity(_ d: float64) -> float64 {
    if d.isNaN || d == 0 { return 0 }
    if d.isInfinite { return d }
    return d.rounded(.towardZero)
}

/// IsIntegral says whether a double is an integer (Number.isInteger).
public func IsIntegral(_ d: float64) -> bool {
    return !d.isNaN && !d.isInfinite && d == d.rounded(.towardZero)
}
