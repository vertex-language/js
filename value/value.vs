// Package value is the engine's primitive layer: symbols, property keys,
// BigInts, and the conversions between numbers and strings that the
// language defines exactly (ECMA-262 §6.1, §7.1).
//
// The Value type itself lives in js/object beside JSObject, so that an
// object held in a Value needs no downcast.
package value

import (
    "js/str"
)

var nextSymbolID: int = 1

/// Symbol is an ECMAScript symbol. Private names (#x) are symbols too,
/// marked private, so they share property storage but never show up in
/// reflection.
public final class Symbol: Hashable {
    public let Description: str.JSString?
    public let ID: int
    public let IsPrivate: bool
    /// RegistryKey is set for symbols from Symbol.for.
    public var RegistryKey: str.JSString? = nil

    public init(_ description: str.JSString?, isPrivate: bool = false) {
        self.Description = description
        self.IsPrivate = isPrivate
        self.ID = nextSymbolID
        nextSymbolID += 1
    }

    public static func ==(a: Symbol, b: Symbol) -> bool { return a === b }

    public func hash(into hasher: inout Hasher) { hasher.combine(ID) }

    /// DescriptiveString is Symbol(description).
    public var DescriptiveString: string {
        if IsPrivate { return Description?.String ?? "#" }
        return "Symbol(\(Description?.String ?? ""))"
    }
}

/// The well-known symbols (§6.1.5.1), shared by every realm.
public let SymAsyncIterator = Symbol(str.JSString.From("Symbol.asyncIterator"))
public let SymHasInstance = Symbol(str.JSString.From("Symbol.hasInstance"))
public let SymIsConcatSpreadable = Symbol(str.JSString.From("Symbol.isConcatSpreadable"))
public let SymIterator = Symbol(str.JSString.From("Symbol.iterator"))
public let SymMatch = Symbol(str.JSString.From("Symbol.match"))
public let SymMatchAll = Symbol(str.JSString.From("Symbol.matchAll"))
public let SymReplace = Symbol(str.JSString.From("Symbol.replace"))
public let SymSearch = Symbol(str.JSString.From("Symbol.search"))
public let SymSpecies = Symbol(str.JSString.From("Symbol.species"))
public let SymSplit = Symbol(str.JSString.From("Symbol.split"))
public let SymToPrimitive = Symbol(str.JSString.From("Symbol.toPrimitive"))
public let SymToStringTag = Symbol(str.JSString.From("Symbol.toStringTag"))
public let SymUnscopables = Symbol(str.JSString.From("Symbol.unscopables"))
public let SymDispose = Symbol(str.JSString.From("Symbol.dispose"))
public let SymAsyncDispose = Symbol(str.JSString.From("Symbol.asyncDispose"))

/// PropertyKey is a property's name: an array index, a string, or a
/// symbol. A string that is a canonical array index is always stored as
/// .index, so the two spellings of one key are one key.
public enum PropertyKey: Hashable {
    case index(uint32)
    case string(str.JSString)
    case symbol(Symbol)

    public static func ==(a: PropertyKey, b: PropertyKey) -> bool {
        switch a {
        case .index(let x):
            if case .index(let y) = b { return x == y }
            return false
        case .string(let x):
            if case .string(let y) = b { return x.Equals(y) }
            return false
        case .symbol(let x):
            if case .symbol(let y) = b { return x === y }
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .index(let i): hasher.combine(int(i))
        case .string(let s): hasher.combine(s.HashCode)
        case .symbol(let s): hasher.combine(s.ID &* 31)
        }
    }

    /// FromString canonicalizes a string key.
    public static func FromString(_ s: str.JSString) -> PropertyKey {
        if let i = ArrayIndex(s) { return .index(i) }
        return .string(s)
    }

    /// Named makes a key from a UTF-8 name, interned.
    public static func Named(_ s: string) -> PropertyKey {
        return FromString(str.Name(s))
    }

    /// FromNumber is ToPropertyKey of a number.
    public static func FromNumber(_ d: float64) -> PropertyKey {
        if d >= 0 && d < 4294967295.0 && d == d.rounded(.towardZero) {
            if d == 0 && d.sign == .minus { return .index(0) }
            return .index(uint32(d))
        }
        return .string(NumberToJSString(d))
    }

    public var IsSymbol: bool {
        if case .symbol = self { return true }
        return false
    }

    public var IsPrivate: bool {
        if case .symbol(let s) = self { return s.IsPrivate }
        return false
    }

    /// AsString is the key as a string (a symbol's description for symbols).
    public var AsString: str.JSString {
        switch self {
        case .index(let i): return str.JSString.From("\(i)")
        case .string(let s): return s
        case .symbol(let s): return s.Description ?? str.JSString.Empty
        }
    }

    /// Debug is a readable form of the key.
    public var Debug: string {
        switch self {
        case .index(let i): return "\(i)"
        case .string(let s): return s.String
        case .symbol(let s): return s.DescriptiveString
        }
    }
}

/// ArrayIndex parses a canonical array index: "0" or digits without a
/// leading zero, below 2^32 - 1.
public func ArrayIndex(_ s: str.JSString) -> uint32? {
    let n = s.Length
    if n == 0 || n > 10 { return nil }
    let u = s.Units
    if u[0] == 0x30 { return n == 1 ? 0 : nil }
    var v: uint64 = 0
    for c in u {
        if c < 0x30 || c > 0x39 { return nil }
        v = v * 10 + uint64(c - 0x30)
    }
    if v >= 4294967295 { return nil }
    return uint32(v)
}
