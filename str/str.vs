// Package str is ECMAScript's String type: a sequence of UTF-16 code
// units (ECMA-262 §6.1.4).
//
// Concatenation builds a rope, so a loop that appends to a string costs
// linear time; the rope is flattened the first time its units are read.
package str

import (
    "unicode/utf16"
)

/// JSString is an immutable string of UTF-16 code units.
public final class JSString: Hashable, CustomStringConvertible {
    var flat: [uint16]
    var left: JSString?
    var right: JSString?
    var isFlat: bool
    public let Length: int
    var hashCache: int = 0
    var hashed: bool = false
    var utf8: string? = nil

    public init(_ units: [uint16]) {
        self.flat = units
        self.left = nil
        self.right = nil
        self.isFlat = true
        self.Length = units.count
    }

    init(left: JSString, right: JSString) {
        self.flat = []
        self.left = left
        self.right = right
        self.isFlat = false
        self.Length = left.Length + right.Length
    }

    /// From makes a JSString from a UTF-8 string.
    public static func From(_ s: string) -> JSString {
        let j = JSString(utf16.Encode(s))
        j.utf8 = s
        return j
    }

    public static let Empty = JSString([])

    /// Units are the code units, flattening a rope.
    public var Units: [uint16] {
        if !isFlat { flatten() }
        return flat
    }

    func flatten() {
        var out: [uint16] = []
        out.reserveCapacity(Length)
        // Walk the rope without recursion: ropes built in a loop are deep.
        var stack: [JSString] = [self]
        while !stack.isEmpty {
            let n = stack.removeLast()
            if n.isFlat {
                out.append(contentsOf: n.flat)
            } else {
                stack.append(n.right!)
                stack.append(n.left!)
            }
        }
        flat = out
        isFlat = true
        left = nil
        right = nil
    }

    public var IsEmpty: bool { return Length == 0 }

    /// At is the code unit at i, which must be in range.
    public func At(_ i: int) -> uint16 {
        if !isFlat { flatten() }
        return flat[i]
    }

    /// CodePointAt joins a surrogate pair at i.
    public func CodePointAt(_ i: int) -> (cp: uint32, width: int) {
        if !isFlat { flatten() }
        let r = utf16.DecodeAt(flat, i)
        return (r.codePoint, r.width)
    }

    /// Concat joins two strings.
    public func Concat(_ other: JSString) -> JSString {
        if Length == 0 { return other }
        if other.Length == 0 { return self }
        if Length + other.Length < 32 {
            var u = Units
            u.append(contentsOf: other.Units)
            return JSString(u)
        }
        return JSString(left: self, right: other)
    }

    /// Slice is the substring [from, to).
    public func Slice(_ from: int, _ to: int) -> JSString {
        if from <= 0 && to >= Length { return self }
        if from >= to { return JSString.Empty }
        if !isFlat { flatten() }
        var out: [uint16] = []
        out.reserveCapacity(to - from)
        var i = from
        while i < to { out.append(flat[i]); i += 1 }
        return JSString(out)
    }

    /// IndexOf finds needle at or after from, or returns -1.
    public func IndexOf(_ needle: JSString, from: int) -> int {
        let n = needle.Length
        let h = Units
        let nd = needle.Units
        var i = from < 0 ? 0 : from
        if n == 0 { return i <= Length ? i : -1 }
        while i + n <= Length {
            if h[i] == nd[0] {
                var j = 1
                while j < n && h[i + j] == nd[j] { j += 1 }
                if j == n { return i }
            }
            i += 1
        }
        return -1
    }

    /// LastIndexOf finds needle at or before from, or returns -1.
    public func LastIndexOf(_ needle: JSString, from: int) -> int {
        let n = needle.Length
        let h = Units
        let nd = needle.Units
        var i = from
        if i + n > Length { i = Length - n }
        while i >= 0 {
            var j = 0
            while j < n && h[i + j] == nd[j] { j += 1 }
            if j == n { return i }
            i -= 1
        }
        return -1
    }

    public func StartsWith(_ p: JSString, at: int) -> bool {
        if at < 0 || at + p.Length > Length { return false }
        let h = Units
        let pu = p.Units
        var j = 0
        while j < p.Length {
            if h[at + j] != pu[j] { return false }
            j += 1
        }
        return true
    }

    /// Compare orders by code units, as the < operator does.
    public func Compare(_ other: JSString) -> int {
        let a = Units
        let b = other.Units
        let n = a.count < b.count ? a.count : b.count
        var i = 0
        while i < n {
            if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
            i += 1
        }
        if a.count == b.count { return 0 }
        return a.count < b.count ? -1 : 1
    }

    /// Equals compares code units.
    public func Equals(_ other: JSString) -> bool {
        if self === other { return true }
        if Length != other.Length { return false }
        if hashed && other.hashed && hashCache != other.hashCache { return false }
        let a = Units
        let b = other.Units
        var i = 0
        while i < a.count {
            if a[i] != b[i] { return false }
            i += 1
        }
        return true
    }

    /// EqualsASCII compares with an ASCII literal without allocating.
    public func EqualsASCII(_ s: string) -> bool {
        let a = Units
        var i = 0
        for b in s.utf8 {
            if i >= a.count || a[i] != uint16(b) { return false }
            i += 1
        }
        return i == a.count
    }

    public static func ==(lhs: JSString, rhs: JSString) -> bool {
        return lhs.Equals(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(HashCode)
    }

    /// HashCode is FNV-1a over the code units, cached.
    public var HashCode: int {
        if hashed { return hashCache }
        var h: uint64 = 14695981039346656037
        for u in Units {
            h = (h ^ uint64(u)) &* 1099511628211
        }
        hashCache = int(truncatingIfNeeded: h)
        hashed = true
        return hashCache
    }

    /// String is the UTF-8 form (lone surrogates become U+FFFD).
    public var String: string {
        if let s = utf8 { return s }
        let s = utf16.Decode(Units)
        utf8 = s
        return s
    }

    public var description: string { return String }

    /// IsASCIIDigits says whether the string is non-empty decimal digits.
    public var IsASCIIDigits: bool {
        if Length == 0 { return false }
        for u in Units {
            if u < 0x30 || u > 0x39 { return false }
        }
        return true
    }
}

/// Intern returns the one JSString for an ASCII or UTF-8 name, so names
/// the compiler and the built-ins share are the same object and compare
/// by identity first.
public final class AtomTable {
    var table: [string: JSString] = [:]

    public init() {}

    public func Intern(_ text: string) -> JSString {
        if let existing = table[text] {
            return existing
        }
        let s = JSString.From(text)
        _ = s.HashCode
        table[text] = s
        return s
    }
}

/// Atoms is the process-wide table.
public let Atoms = AtomTable()

/// Name interns a UTF-8 name.
public func Name(_ s: string) -> JSString {
    return Atoms.Intern(s)
}

/// Builder accumulates code units.
public struct Builder {
    public var Units: [uint16] = []

    public init() {}

    public mutating func Append(_ s: JSString) {
        Units.append(contentsOf: s.Units)
    }

    public mutating func AppendASCII(_ s: string) {
        for b in s.utf8 { Units.append(uint16(b)) }
    }

    public mutating func AppendString(_ s: string) {
        Units.append(contentsOf: utf16.Encode(s))
    }

    public mutating func AppendUnit(_ u: uint16) {
        Units.append(u)
    }

    public mutating func AppendCodePoint(_ cp: uint32) {
        utf16.Append(&Units, cp)
    }

    public func Build() -> JSString {
        return JSString(Units)
    }
}
