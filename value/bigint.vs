package value

import "js/str"

// MARK: natural numbers
//
// A natural number is little-endian base-2^32 limbs with no high zero limbs;
// zero is the empty array. BigInt and the exact decimal conversions in
// number.vs are built on these.

func natTrim(_ a: inout [uint32]) {
    while !a.isEmpty && a[a.count - 1] == 0 { _ = a.removeLast() }
}

func natCompare(_ a: [uint32], _ b: [uint32]) -> int {
    if a.count != b.count { return a.count < b.count ? -1 : 1 }
    var i = a.count - 1
    while i >= 0 {
        if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        i -= 1
    }
    return 0
}

func natAdd(_ a: [uint32], _ b: [uint32]) -> [uint32] {
    let n = a.count > b.count ? a.count : b.count
    var out: [uint32] = []
    out.reserveCapacity(n + 1)
    var carry: uint64 = 0
    var i = 0
    while i < n {
        var s = carry
        if i < a.count { s += uint64(a[i]) }
        if i < b.count { s += uint64(b[i]) }
        out.append(uint32(truncatingIfNeeded: s))
        carry = s >> 32
        i += 1
    }
    if carry != 0 { out.append(uint32(carry)) }
    return out
}

/// natSub is a - b, where a >= b.
func natSub(_ a: [uint32], _ b: [uint32]) -> [uint32] {
    var out: [uint32] = []
    out.reserveCapacity(a.count)
    var borrow: int64 = 0
    var i = 0
    while i < a.count {
        var d = int64(a[i]) - borrow
        if i < b.count { d -= int64(b[i]) }
        if d < 0 {
            d += 4294967296
            borrow = 1
        } else {
            borrow = 0
        }
        out.append(uint32(d))
        i += 1
    }
    natTrim(&out)
    return out
}

func natMul(_ a: [uint32], _ b: [uint32]) -> [uint32] {
    if a.isEmpty || b.isEmpty { return [] }
    var out = [uint32](repeating: 0, count: a.count + b.count)
    var i = 0
    while i < a.count {
        var carry: uint64 = 0
        let ai = uint64(a[i])
        var j = 0
        while j < b.count {
            let t = ai * uint64(b[j]) + uint64(out[i + j]) + carry
            out[i + j] = uint32(truncatingIfNeeded: t)
            carry = t >> 32
            j += 1
        }
        var k = i + b.count
        while carry != 0 {
            let t = uint64(out[k]) + carry
            out[k] = uint32(truncatingIfNeeded: t)
            carry = t >> 32
            k += 1
        }
        i += 1
    }
    natTrim(&out)
    return out
}

func natMulSmall(_ a: [uint32], _ m: uint32, add: uint32 = 0) -> [uint32] {
    var out: [uint32] = []
    out.reserveCapacity(a.count + 1)
    var carry = uint64(add)
    for x in a {
        let t = uint64(x) * uint64(m) + carry
        out.append(uint32(truncatingIfNeeded: t))
        carry = t >> 32
    }
    if carry != 0 { out.append(uint32(carry)) }
    natTrim(&out)
    return out
}

/// natDivSmall divides by a small divisor, returning quotient and remainder.
func natDivSmall(_ a: [uint32], _ d: uint32) -> (q: [uint32], r: uint32) {
    var q = [uint32](repeating: 0, count: a.count)
    var r: uint64 = 0
    var i = a.count - 1
    while i >= 0 {
        let cur = (r << 32) | uint64(a[i])
        q[i] = uint32(cur / uint64(d))
        r = cur % uint64(d)
        i -= 1
    }
    natTrim(&q)
    return (q, uint32(r))
}

func natShiftLeft(_ a: [uint32], _ n: int) -> [uint32] {
    if a.isEmpty { return [] }
    let limbs = n / 32
    let bits = n % 32
    var out = [uint32](repeating: 0, count: limbs)
    if bits == 0 {
        out.append(contentsOf: a)
    } else {
        var carry: uint32 = 0
        for x in a {
            out.append((x << uint32(bits)) | carry)
            carry = x >> uint32(32 - bits)
        }
        if carry != 0 { out.append(carry) }
    }
    return out
}

func natShiftRight(_ a: [uint32], _ n: int) -> [uint32] {
    let limbs = n / 32
    let bits = n % 32
    if limbs >= a.count { return [] }
    var out: [uint32] = []
    var i = limbs
    while i < a.count {
        var v = a[i] >> uint32(bits)
        if bits != 0 && i + 1 < a.count {
            v |= a[i + 1] << uint32(32 - bits)
        }
        out.append(v)
        i += 1
    }
    natTrim(&out)
    return out
}

func natBitLength(_ a: [uint32]) -> int {
    if a.isEmpty { return 0 }
    var top = a[a.count - 1]
    var bits = 0
    while top != 0 { bits += 1; top >>= 1 }
    return (a.count - 1) * 32 + bits
}

/// natDivMod is long division (Knuth's algorithm D, bit by bit for
/// simplicity on the rare large divisions).
func natDivMod(_ a: [uint32], _ b: [uint32]) -> (q: [uint32], r: [uint32]) {
    if natCompare(a, b) < 0 { return ([], a) }
    if b.count == 1 {
        let (q, r) = natDivSmall(a, b[0])
        return (q, r == 0 ? [] : [r])
    }
    // Normalize so the divisor's top limb has its high bit set.
    let shift = 32 - (natBitLength(b) - (b.count - 1) * 32)
    let u0 = natShiftLeft(a, shift)
    let v = natShiftLeft(b, shift)
    var u = u0
    if u.count == a.count { u.append(0) }
    if u.count < a.count + 1 { while u.count < a.count + 1 { u.append(0) } }
    let n = v.count
    let m = u.count - n
    var q = [uint32](repeating: 0, count: m)
    let vTop = uint64(v[n - 1])
    let vNext = uint64(v[n - 2])
    var j = m - 1
    while j >= 0 {
        let num = (uint64(u[j + n]) << 32) | uint64(u[j + n - 1])
        var qhat = num / vTop
        var rhat = num % vTop
        while qhat >= 4294967296 || qhat * vNext > ((rhat << 32) | uint64(u[j + n - 2])) {
            qhat -= 1
            rhat += vTop
            if rhat >= 4294967296 { break }
        }
        // Multiply and subtract.
        var borrow: int64 = 0
        var carry: uint64 = 0
        var i = 0
        while i < n {
            let p = qhat * uint64(v[i]) + carry
            carry = p >> 32
            let t = int64(u[i + j]) - borrow - int64(p & 0xFFFFFFFF)
            u[i + j] = uint32(truncatingIfNeeded: t)
            borrow = t < 0 ? 1 : 0
            i += 1
        }
        let t = int64(u[j + n]) - borrow - int64(carry)
        u[j + n] = uint32(truncatingIfNeeded: t)
        if t < 0 {
            // Add back.
            qhat -= 1
            var c: uint64 = 0
            i = 0
            while i < n {
                let s = uint64(u[i + j]) + uint64(v[i]) + c
                u[i + j] = uint32(truncatingIfNeeded: s)
                c = s >> 32
                i += 1
            }
            u[j + n] = uint32(truncatingIfNeeded: uint64(u[j + n]) + c)
        }
        q[j] = uint32(qhat)
        j -= 1
    }
    natTrim(&q)
    var r: [uint32] = []
    var k = 0
    while k < n { r.append(u[k]); k += 1 }
    natTrim(&r)
    r = natShiftRight(r, shift)
    return (q, r)
}

func natFromUInt64(_ v: uint64) -> [uint32] {
    var out: [uint32] = []
    if v != 0 {
        out.append(uint32(truncatingIfNeeded: v))
        if v >> 32 != 0 { out.append(uint32(v >> 32)) }
    }
    return out
}

func natPow(_ base: uint32, _ exp: int) -> [uint32] {
    var result: [uint32] = [1]
    var b: [uint32] = natFromUInt64(uint64(base))
    var e = exp
    while e > 0 {
        if e & 1 == 1 { result = natMul(result, b) }
        e >>= 1
        if e > 0 { b = natMul(b, b) }
    }
    return result
}

/// natToString writes a natural number in a radix from 2 to 36.
func natToString(_ a: [uint32], _ radix: int) -> string {
    if a.isEmpty { return "0" }
    let digits: [uint8] = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122]
    // Divide by the largest power of the radix that fits a limb.
    var chunk: uint32 = uint32(radix)
    var chunkDigits = 1
    while uint64(chunk) * uint64(radix) < 4294967296 {
        chunk *= uint32(radix)
        chunkDigits += 1
    }
    var out: [uint8] = []
    var cur = a
    while !cur.isEmpty {
        let (q, r) = natDivSmall(cur, chunk)
        var rem = r
        var n = 0
        while n < chunkDigits && !(q.isEmpty && rem == 0) {
            out.append(digits[int(rem % uint32(radix))])
            rem /= uint32(radix)
            n += 1
        }
        cur = q
    }
    out.reverse()
    return string(decoding: out, as: UTF8.self)
}

// MARK: BigInt

/// BigInt is an arbitrary-precision integer (§6.1.6.2): a sign and a
/// magnitude. Zero is never negative.
public final class BigInt {
    public let Negative: bool
    let mag: [uint32]

    init(negative: bool, mag: [uint32]) {
        var m = mag
        natTrim(&m)
        self.mag = m
        self.Negative = negative && !m.isEmpty
    }

    public static let Zero = BigInt(negative: false, mag: [])
    public static let One = BigInt(negative: false, mag: [1])

    public static func FromInt(_ v: int64) -> BigInt {
        if v < 0 {
            let m = v == int64.min ? uint64(1) << 63 : uint64(-v)
            return BigInt(negative: true, mag: natFromUInt64(m))
        }
        return BigInt(negative: false, mag: natFromUInt64(uint64(v)))
    }

    public var IsZero: bool { return mag.isEmpty }

    /// FromDouble converts an integral double exactly.
    public static func FromDouble(_ d: float64) -> BigInt {
        if d == 0 { return Zero }
        let neg = d < 0
        let a = neg ? -d : d
        let bits = a.bitPattern
        let exp = int((bits >> 52) & 0x7FF)
        var mant = bits & 0xFFFFFFFFFFFFF
        var e2 = exp - 1075
        if exp == 0 { e2 = -1074 } else { mant |= uint64(1) << 52 }
        var m = natFromUInt64(mant)
        if e2 > 0 {
            m = natShiftLeft(m, e2)
        } else if e2 < 0 {
            m = natShiftRight(m, -e2)
        }
        return BigInt(negative: neg, mag: m)
    }

    /// Parse reads a StringIntegerLiteral: optional whitespace already
    /// trimmed, decimal with a sign, or 0x/0o/0b without one. Nil if invalid.
    public static func Parse(_ text: string) -> BigInt? {
        var b = [uint8](text.utf8)
        if b.isEmpty { return Zero }
        var neg = false
        var radix = 10
        var i = 0
        if b.count > 2 && b[0] == 0x30 && ((b[1] | 0x20) == 0x78 || (b[1] | 0x20) == 0x6F || (b[1] | 0x20) == 0x62) {
            let c = b[1] | 0x20
            radix = c == 0x78 ? 16 : (c == 0x6F ? 8 : 2)
            i = 2
        } else if b[0] == 0x2B || b[0] == 0x2D {
            neg = b[0] == 0x2D
            i = 1
            if b.count == 1 { return nil }
        }
        var mag: [uint32] = []
        if i >= b.count { return nil }
        while i < b.count {
            var d = -1
            let c = b[i]
            if c >= 0x30 && c <= 0x39 { d = int(c - 0x30) } else if (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A { d = int((c | 0x20) - 0x61) + 10 }
            if d < 0 || d >= radix { return nil }
            mag = natMulSmall(mag, uint32(radix), add: uint32(d))
            i += 1
        }
        b = []
        return BigInt(negative: neg, mag: mag)
    }

    /// ParseLiteral reads a BigInt literal's digits as written (0x.. etc).
    public static func ParseLiteral(_ text: string) -> BigInt {
        return Parse(text) ?? Zero
    }

    public func ToString(_ radix: int = 10) -> string {
        let s = natToString(mag, radix)
        return Negative ? "-" + s : s
    }

    public func ToDouble() -> float64 {
        if mag.isEmpty { return 0 }
        let bl = natBitLength(mag)
        var d: float64
        if bl <= 64 {
            var v: uint64 = 0
            var i = mag.count - 1
            while i >= 0 { v = (v << 32) | uint64(mag[i]); i -= 1 }
            d = float64(v)
            if bl > 53 {
                // float64(uint64) rounds to nearest even already.
            }
        } else {
            // Keep 64 top bits plus a sticky bit, then scale.
            let shift = bl - 64
            let top = natShiftRight(mag, shift)
            var v: uint64 = 0
            var i = top.count - 1
            while i >= 0 { v = (v << 32) | uint64(top[i]); i -= 1 }
            // Sticky: any bit below the kept ones makes the value inexact.
            let back = natShiftLeft(top, shift)
            if natCompare(back, mag) != 0 { v |= 1 }
            // Round to 53 bits by hand: float64(uint64) would round from 64
            // bits, but the sticky bit carries the rest.
            let lz = 11
            var m = v >> uint64(lz)
            let rem = v & ((uint64(1) << uint64(lz)) - 1)
            let half = uint64(1) << uint64(lz - 1)
            if rem > half || (rem == half && (m & 1) == 1) { m += 1 }
            d = float64(m) * pow2(shift + lz)
        }
        return Negative ? -d : d
    }

    public static func Compare(_ a: BigInt, _ b: BigInt) -> int {
        if a.Negative != b.Negative { return a.Negative ? -1 : 1 }
        let c = natCompare(a.mag, b.mag)
        return a.Negative ? -c : c
    }

    public static func Equal(_ a: BigInt, _ b: BigInt) -> bool {
        return a.Negative == b.Negative && natCompare(a.mag, b.mag) == 0
    }

    public func Negate() -> BigInt { return BigInt(negative: !Negative, mag: mag) }

    public static func Add(_ a: BigInt, _ b: BigInt) -> BigInt {
        if a.Negative == b.Negative { return BigInt(negative: a.Negative, mag: natAdd(a.mag, b.mag)) }
        let c = natCompare(a.mag, b.mag)
        if c == 0 { return Zero }
        if c > 0 { return BigInt(negative: a.Negative, mag: natSub(a.mag, b.mag)) }
        return BigInt(negative: b.Negative, mag: natSub(b.mag, a.mag))
    }

    public static func Sub(_ a: BigInt, _ b: BigInt) -> BigInt {
        return Add(a, b.Negate())
    }

    public static func Mul(_ a: BigInt, _ b: BigInt) -> BigInt {
        return BigInt(negative: a.Negative != b.Negative, mag: natMul(a.mag, b.mag))
    }

    /// Div truncates toward zero; the divisor must not be zero.
    public static func Div(_ a: BigInt, _ b: BigInt) -> BigInt {
        let (q, _) = natDivMod(a.mag, b.mag)
        return BigInt(negative: a.Negative != b.Negative, mag: q)
    }

    /// Rem takes the dividend's sign; the divisor must not be zero.
    public static func Rem(_ a: BigInt, _ b: BigInt) -> BigInt {
        let (_, r) = natDivMod(a.mag, b.mag)
        return BigInt(negative: a.Negative, mag: r)
    }

    /// Pow raises to a non-negative exponent.
    public static func Pow(_ a: BigInt, _ e: BigInt) -> BigInt {
        var result = One
        var base = a
        var exp = e.mag
        while !exp.isEmpty {
            if exp[0] & 1 == 1 { result = Mul(result, base) }
            exp = natShiftRight(exp, 1)
            if !exp.isEmpty { base = Mul(base, base) }
        }
        return result
    }

    // Two's complement for the bitwise operators: an infinite sign
    // extension, done over enough limbs.
    func twos(_ limbs: int) -> [uint32] {
        var out = [uint32](repeating: 0, count: limbs)
        var i = 0
        while i < mag.count && i < limbs { out[i] = mag[i]; i += 1 }
        if Negative {
            var carry: uint64 = 1
            i = 0
            while i < limbs {
                let t = uint64(~out[i]) + carry
                out[i] = uint32(truncatingIfNeeded: t)
                carry = t >> 32
                i += 1
            }
        }
        return out
    }

    static func fromTwos(_ t: [uint32]) -> BigInt {
        let neg = !t.isEmpty && (t[t.count - 1] & 0x80000000) != 0
        if !neg { return BigInt(negative: false, mag: t) }
        var out = t
        var carry: uint64 = 1
        var i = 0
        while i < out.count {
            let x = uint64(~out[i]) + carry
            out[i] = uint32(truncatingIfNeeded: x)
            carry = x >> 32
            i += 1
        }
        return BigInt(negative: true, mag: out)
    }

    public static func BitOp(_ a: BigInt, _ b: BigInt, _ op: int) -> BigInt {
        let n = (a.mag.count > b.mag.count ? a.mag.count : b.mag.count) + 1
        let x = a.twos(n)
        let y = b.twos(n)
        var out = [uint32](repeating: 0, count: n)
        var i = 0
        while i < n {
            if op == 0 { out[i] = x[i] & y[i] } else if op == 1 { out[i] = x[i] | y[i] } else { out[i] = x[i] ^ y[i] }
            i += 1
        }
        return fromTwos(out)
    }

    public func BitNot() -> BigInt {
        // ~x = -x - 1
        return BigInt.Sub(self.Negate(), BigInt.One)
    }

    /// ShiftLeft shifts by a signed amount (negative shifts right,
    /// rounding toward negative infinity).
    public static func ShiftLeft(_ a: BigInt, _ n: int) -> BigInt {
        if n >= 0 { return BigInt(negative: a.Negative, mag: natShiftLeft(a.mag, n)) }
        let s = -n
        if !a.Negative { return BigInt(negative: false, mag: natShiftRight(a.mag, s)) }
        // Floor division for negatives.
        let q = natShiftRight(a.mag, s)
        let back = natShiftLeft(q, s)
        if natCompare(back, a.mag) != 0 {
            return BigInt(negative: true, mag: natAdd(q, [1]))
        }
        return BigInt(negative: true, mag: q)
    }

    /// AsUintN is BigInt.asUintN.
    public static func AsUintN(_ bits: int, _ a: BigInt) -> BigInt {
        if bits == 0 { return Zero }
        let limbs = (bits + 31) / 32 + 1
        var t = a.twos(limbs)
        var i = 0
        while i < t.count {
            let lo = i * 32
            if lo >= bits {
                t[i] = 0
            } else if lo + 32 > bits {
                t[i] &= (uint32(1) << uint32(bits - lo)) - 1
            }
            i += 1
        }
        return BigInt(negative: false, mag: t)
    }

    /// AsIntN is BigInt.asIntN.
    public static func AsIntN(_ bits: int, _ a: BigInt) -> BigInt {
        if bits == 0 { return Zero }
        let u = AsUintN(bits, a)
        // If bit (bits-1) is set, subtract 2^bits.
        if natBitLength(u.mag) == bits {
            return Sub(u, BigInt(negative: false, mag: natShiftLeft([1], bits)))
        }
        return u
    }

    /// ToInt64 wraps modulo 2^64.
    public func ToInt64() -> int64 {
        let t = twos(3)
        return int64(bitPattern: (uint64(t[1]) << 32) | uint64(t[0]))
    }

    public func ToUInt64() -> uint64 {
        let t = twos(3)
        return (uint64(t[1]) << 32) | uint64(t[0])
    }

    public var JSString: str.JSString { return str.JSString.From(ToString(10)) }
}

func pow2(_ n: int) -> float64 {
    var r: float64 = 1
    var i = 0
    if n >= 0 {
        while i < n { r *= 2; i += 1 }
    } else {
        while i < -n { r /= 2; i += 1 }
    }
    return r
}
