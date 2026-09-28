package str

/// JSString implements ECMAScript UTF-16 strings with Latin-1 and two-byte storage.
public final class JSString: Equatable, CustomStringConvertible {
    public let IsLatin1: bool
    let latin1Bytes: [uint8]
    let utf16Units: [uint16]
    public let Length: int

    public init(latin1: [uint8]) {
        self.IsLatin1 = true
        self.latin1Bytes = latin1
        self.utf16Units = []
        self.Length = latin1.count
    }

    public init(utf16: [uint16]) {
        self.IsLatin1 = false
        self.latin1Bytes = []
        self.utf16Units = utf16
        self.Length = utf16.count
    }

    /// FromUTF8 creates a JSString from a Vertex UTF-8 string.
    public static func FromUTF8(_ text: string) -> JSString {
        var u16: [uint16] = []
        for s in text.unicodeScalars {
            let v = s.value
            if v < 0x10000 {
                u16.append(uint16(v))
            } else {
                let shifted = v - 0x10000
                u16.append(uint16(0xD800 + (shifted >> 10)))
                u16.append(uint16(0xDC00 + (shifted & 0x3FF)))
            }
        }
        var fitsLatin1 = true
        for u in u16 {
            if u > 0xFF {
                fitsLatin1 = false
                break
            }
        }
        if fitsLatin1 {
            var b: [uint8] = []
            for u in u16 {
                b.append(uint8(u))
            }
            return JSString(latin1: b)
        }
        return JSString(utf16: u16)
    }

    /// ToUTF8 converts the JSString to a Vertex UTF-8 string.
    public func ToUTF8() -> string {
        var utf8Bytes: [uint8] = []
        var i = 0
        while i < Length {
            let cp = CodePointAt(i)
            if cp >= 0x10000 {
                i += 2
            } else {
                i += 1
            }
            if cp <= 0x7F {
                utf8Bytes.append(uint8(cp))
            } else if cp <= 0x7FF {
                utf8Bytes.append(uint8(0xC0 | (cp >> 6)))
                utf8Bytes.append(uint8(0x80 | (cp & 0x3F)))
            } else if cp <= 0xFFFF {
                utf8Bytes.append(uint8(0xE0 | (cp >> 12)))
                utf8Bytes.append(uint8(0x80 | ((cp >> 6) & 0x3F)))
                utf8Bytes.append(uint8(0x80 | (cp & 0x3F)))
            } else {
                utf8Bytes.append(uint8(0xF0 | (cp >> 18)))
                utf8Bytes.append(uint8(0x80 | ((cp >> 12) & 0x3F)))
                utf8Bytes.append(uint8(0x80 | ((cp >> 6) & 0x3F)))
                utf8Bytes.append(uint8(0x80 | (cp & 0x3F)))
            }
        }
        return String(decoding: utf8Bytes, as: UTF8.self)
    }

    /// CharCodeAt returns the 16-bit code unit at index.
    public func CharCodeAt(_ index: int) -> uint16 {
        if index < 0 || index >= Length {
            return 0
        }
        if IsLatin1 {
            return uint16(latin1Bytes[index])
        }
        return utf16Units[index]
    }

    /// CodePointAt returns the Unicode code point at index.
    public func CodePointAt(_ index: int) -> uint32 {
        if index < 0 || index >= Length {
            return 0
        }
        let first = uint32(CharCodeAt(index))
        if first < 0xD800 || first > 0xDBFF || index + 1 >= Length {
            return first
        }
        let second = uint32(CharCodeAt(index + 1))
        if second < 0xDC00 || second > 0xDFFF {
            return first
        }
        return ((first - 0xD800) << 10) + (second - 0xDC00) + 0x10000
    }

    /// Substring returns a slice from start up to end.
    public func Substring(start: int, end: int) -> JSString {
        let s = start < 0 ? 0 : (start > Length ? Length : start)
        let e = end < 0 ? 0 : (end > Length ? Length : end)
        let from = s < e ? s : e
        let to = s < e ? e : s
        if from == to {
            return JSString(latin1: [])
        }
        if IsLatin1 {
            var sub: [uint8] = []
            for i in from..<to { sub.append(latin1Bytes[i]) }
            return JSString(latin1: sub)
        }
        var sub: [uint16] = []
        for i in from..<to { sub.append(utf16Units[i]) }
        return JSString(utf16: sub)
    }

    /// Concat concatenates this string with other.
    public func Concat(_ other: JSString) -> JSString {
        if Length == 0 { return other }
        if other.Length == 0 { return self }
        if IsLatin1 && other.IsLatin1 {
            var b = latin1Bytes
            for x in other.latin1Bytes { b.append(x) }
            return JSString(latin1: b)
        }
        var units: [uint16] = []
        for i in 0..<Length { units.append(CharCodeAt(i)) }
        for i in 0..<other.Length { units.append(other.CharCodeAt(i)) }
        return JSString(utf16: units)
    }

    public static func ==(lhs: JSString, rhs: JSString) -> bool {
        if lhs.Length != rhs.Length { return false }
        if lhs.IsLatin1 && rhs.IsLatin1 {
            for i in 0..<lhs.Length {
                if lhs.latin1Bytes[i] != rhs.latin1Bytes[i] { return false }
            }
            return true
        }
        for i in 0..<lhs.Length {
            if lhs.CharCodeAt(i) != rhs.CharCodeAt(i) { return false }
        }
        return true
    }

    public var description: string {
        return ToUTF8()
    }
}

/// AtomTable interns common string property keys for fast pointer equality.
public final class AtomTable {
    var table: [string: JSString] = [:]

    public init() {}

    public func Intern(_ text: string) -> JSString {
        if let existing = table[text] {
            return existing
        }
        let s = JSString.FromUTF8(text)
        table[text] = s
        return s
    }
}
