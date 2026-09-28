// Package object is the runtime's object model: the Value type, objects
// and their internal methods (ECMA-262 §10), the realm and its
// intrinsics, and the abstract operations of §7 that everything above
// (the interpreter, the built-ins) is written in terms of.
package object

import (
    "js/str"
    "js/value"
)

/// Value is an ECMAScript language value (§6.1).
public enum Value {
    case undefined
    case null
    case bool(bool)
    case number(float64)
    case string(str.JSString)
    case symbol(value.Symbol)
    case bigint(value.BigInt)
    case object(JSObject)
    /// empty is the engine's own marker, never a language value: an
    /// uninitialized binding (the temporal dead zone) or an array hole.
    case empty

    public static let True = Value.bool(true)
    public static let False = Value.bool(false)
    public static let Zero = Value.number(0)

    public static func Str(_ s: string) -> Value { return .string(str.JSString.From(s)) }
    public static func Name(_ s: string) -> Value { return .string(str.Name(s)) }
    public static func Int(_ i: int) -> Value { return .number(float64(i)) }

    public var IsUndefined: bool {
        if case .undefined = self { return true }
        return false
    }

    public var IsNull: bool {
        if case .null = self { return true }
        return false
    }

    public var IsNullish: bool {
        switch self {
        case .undefined, .null: return true
        default: return false
        }
    }

    public var IsEmpty: bool {
        if case .empty = self { return true }
        return false
    }

    public var IsObject: bool {
        if case .object = self { return true }
        return false
    }

    public var AsObject: JSObject? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var IsString: bool {
        if case .string = self { return true }
        return false
    }

    public var IsNumber: bool {
        if case .number = self { return true }
        return false
    }

    public var IsCallable: bool {
        if case .object(let o) = self { return o.IsCallable }
        return false
    }

    public var IsConstructor: bool {
        if case .object(let o) = self { return o.IsConstructor }
        return false
    }

    /// TypeOf is the typeof operator's answer.
    public var TypeOf: string {
        switch self {
        case .undefined, .empty: return "undefined"
        case .null: return "object"
        case .bool: return "boolean"
        case .number: return "number"
        case .string: return "string"
        case .symbol: return "symbol"
        case .bigint: return "bigint"
        case .object(let o):
            if o.IsHTMLDDA { return "undefined" }
            return o.IsCallable ? "function" : "object"
        }
    }

    /// ToBoolean (§7.1.2).
    public var Truthy: bool {
        switch self {
        case .undefined, .null, .empty: return false
        case .bool(let b): return b
        case .number(let d): return !(d == 0 || d.isNaN)
        case .string(let s): return s.Length > 0
        case .symbol: return true
        case .bigint(let b): return !b.IsZero
        case .object(let o): return !o.IsHTMLDDA
        }
    }
}

/// SameValue (§7.2.10): NaN is itself, and +0 and -0 differ.
public func SameValue(_ x: Value, _ y: Value) -> bool {
    if case .number(let a) = x, case .number(let b) = y {
        if a.isNaN && b.isNaN { return true }
        if a == 0 && b == 0 { return (a.sign == .minus) == (b.sign == .minus) }
        return a == b
    }
    return StrictEquals(x, y)
}

/// SameValueZero (§7.2.11): NaN is itself, and +0 equals -0.
public func SameValueZero(_ x: Value, _ y: Value) -> bool {
    if case .number(let a) = x, case .number(let b) = y {
        if a.isNaN && b.isNaN { return true }
        return a == b
    }
    return StrictEquals(x, y)
}

/// StrictEquals is IsStrictlyEqual (§7.2.15), the === operator.
public func StrictEquals(_ x: Value, _ y: Value) -> bool {
    switch x {
    case .undefined:
        if case .undefined = y { return true }
        return false
    case .null:
        if case .null = y { return true }
        return false
    case .bool(let a):
        if case .bool(let b) = y { return a == b }
        return false
    case .number(let a):
        if case .number(let b) = y { return a == b }
        return false
    case .string(let a):
        if case .string(let b) = y { return a.Equals(b) }
        return false
    case .symbol(let a):
        if case .symbol(let b) = y { return a === b }
        return false
    case .bigint(let a):
        if case .bigint(let b) = y { return value.BigInt.Equal(a, b) }
        return false
    case .object(let a):
        if case .object(let b) = y { return a === b }
        return false
    case .empty:
        if case .empty = y { return true }
        return false
    }
}
