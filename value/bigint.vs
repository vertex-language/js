package value

import (
    "math/big"
    "js/str"
)

/// BigInt is ECMAScript's BigInt (§6.1.6.2): an immutable
/// arbitrary-precision integer over math/big.Integer, with the operations
/// the language defines on it.
public final class BigInt {
    public let I: big.Integer

    public init(_ i: big.Integer) {
        self.I = i
    }

    public static let Zero = BigInt(big.Integer())
    public static let One = BigInt(big.Integer(1))

    public static func FromInt(_ v: int64) -> BigInt { return BigInt(big.Integer(v)) }

    public var IsZero: bool { return I.IsZero }
    public var Negative: bool { return I.Negative }

    /// FromDouble converts an integral double exactly.
    public static func FromDouble(_ d: float64) -> BigInt { return BigInt(big.Integer.FromFloat64(d)) }

    /// Parse reads a StringIntegerLiteral (whitespace already trimmed):
    /// decimal with an optional sign, or 0x, 0o and 0b without one; the
    /// empty string is 0. Nil if it doesn't match.
    public static func Parse(_ text: string) -> BigInt? {
        let b = [uint8](text.utf8)
        if b.isEmpty { return Zero }
        if b.count > 2 && b[0] == 0x30 {
            let c = b[1] | 0x20
            var radix = 0
            if c == 0x78 { radix = 16 } else if c == 0x6F { radix = 8 } else if c == 0x62 { radix = 2 }
            if radix != 0 {
                guard let n = big.Nat.Parse(string(text.dropFirst(2)), radix: radix) else { return nil }
                return BigInt(big.Integer(n))
            }
        }
        var neg = false
        var digits = text
        if b[0] == 0x2B || b[0] == 0x2D {
            neg = b[0] == 0x2D
            digits = string(text.dropFirst())
        }
        // Only decimal digits: Nat.Parse would take letters in radix 10 as errors anyway.
        guard let n = big.Nat.Parse(digits, radix: 10) else { return nil }
        return BigInt(big.Integer(negative: neg, magnitude: n))
    }

    /// ParseLiteral reads a BigInt literal's digits as the scanner wrote
    /// them (with its 0x, 0o or 0b prefix).
    public static func ParseLiteral(_ text: string) -> BigInt {
        return Parse(text) ?? Zero
    }

    public func ToString(_ radix: int = 10) -> string { return I.ToString(radix) }

    public func ToDouble() -> float64 { return I.ToFloat64() }

    public var JSString: str.JSString { return str.JSString.From(I.ToString(10)) }

    public static func Compare(_ a: BigInt, _ b: BigInt) -> int { return big.Cmp(a.I, b.I) }
    public static func Equal(_ a: BigInt, _ b: BigInt) -> bool { return big.Cmp(a.I, b.I) == 0 }

    public func Negate() -> BigInt { return BigInt(big.Neg(I)) }
    public func BitNot() -> BigInt { return BigInt(big.Not(I)) }

    public static func Add(_ a: BigInt, _ b: BigInt) -> BigInt { return BigInt(big.Add(a.I, b.I)) }
    public static func Sub(_ a: BigInt, _ b: BigInt) -> BigInt { return BigInt(big.Sub(a.I, b.I)) }
    public static func Mul(_ a: BigInt, _ b: BigInt) -> BigInt { return BigInt(big.Mul(a.I, b.I)) }
    /// Div truncates toward zero; b must not be zero.
    public static func Div(_ a: BigInt, _ b: BigInt) -> BigInt { return BigInt(big.Quo(a.I, b.I)) }
    /// Rem takes a's sign; b must not be zero.
    public static func Rem(_ a: BigInt, _ b: BigInt) -> BigInt { return BigInt(big.Rem(a.I, b.I)) }

    /// Pow raises to a non-negative exponent that fits an int.
    public static func Pow(_ a: BigInt, _ e: BigInt) -> BigInt {
        return BigInt(big.Pow(a.I, int(e.I.ToInt64() ?? 0)))
    }

    /// BitOp is & (0), | (1) or ^ (2) on two's complement.
    public static func BitOp(_ a: BigInt, _ b: BigInt, _ op: int) -> BigInt {
        if op == 0 { return BigInt(big.And(a.I, b.I)) }
        if op == 1 { return BigInt(big.Or(a.I, b.I)) }
        return BigInt(big.Xor(a.I, b.I))
    }

    /// ShiftLeft shifts by a signed amount; negative shifts right, rounding
    /// toward negative infinity.
    public static func ShiftLeft(_ a: BigInt, _ n: int) -> BigInt { return BigInt(big.ShiftLeft(a.I, n)) }

    public static func AsUintN(_ bits: int, _ a: BigInt) -> BigInt { return BigInt(big.TruncateUnsigned(a.I, bits)) }
    public static func AsIntN(_ bits: int, _ a: BigInt) -> BigInt { return BigInt(big.TruncateSigned(a.I, bits)) }

    /// ToInt64 wraps modulo 2^64 (BigInt64Array's conversion).
    public func ToInt64() -> int64 { return I.WrappingInt64 }

    public func ToUInt64() -> uint64 { return uint64(bitPattern: I.WrappingInt64) }
}
