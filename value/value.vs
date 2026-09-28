package value

import "gc"

/// ValueType distinguishes the ECMAScript runtime type of a Value.
public enum ValueType: Equatable {
    case undefined
    case null
    case boolean
    case int32
    case number
    case string
    case object
    case symbol
}

/// Value represents an ECMAScript value with unboxed primitives for performance.
public struct Value: Equatable, CustomStringConvertible {
    public var Type: ValueType
    public var IntVal: int32
    public var DoubleVal: float64
    public var StrVal: string
    public var ObjVal: gc.Cell?

    public init(type: ValueType = .undefined, intVal: int32 = 0, doubleVal: float64 = 0.0, strVal: string = "", objVal: gc.Cell? = nil) {
        self.Type = type
        self.IntVal = intVal
        self.DoubleVal = doubleVal
        self.StrVal = strVal
        self.ObjVal = objVal
    }

    public static let Undefined = Value(type: .undefined)
    public static let Null = Value(type: .null)
    public static let True = Value(type: .boolean, intVal: 1)
    public static let False = Value(type: .boolean, intVal: 0)

    public static func Boolean(_ b: bool) -> Value {
        return b ? True : False
    }

    public static func Int(_ i: int32) -> Value {
        return Value(type: .int32, intVal: i, doubleVal: float64(i))
    }

    public static func Number(_ d: float64) -> Value {
        var i: int32 = 0
        if !d.isNaN && !d.isInfinite && d >= -2147483648.0 && d <= 2147483647.0 {
            i = int32(d)
        }
        return Value(type: .number, intVal: i, doubleVal: d)
    }

    public static func String(_ s: string) -> Value {
        return Value(type: .string, strVal: s)
    }

    public static func Object(_ obj: gc.Cell) -> Value {
        return Value(type: .object, objVal: obj)
    }

    // Type queries
    public var IsUndefined: bool { return Type == .undefined }
    public var IsNull: bool { return Type == .null }
    public var IsNullOrUndefined: bool { return Type == .null || Type == .undefined }
    public var IsBoolean: bool { return Type == .boolean }
    public var IsNumber: bool { return Type == .int32 || Type == .number }
    public var IsString: bool { return Type == .string }
    public var IsObject: bool { return Type == .object && ObjVal != nil }

    // ECMAScript Type Conversions (§7.1)

    /// ToBoolean implements ECMA-262 §7.1.2.
    public func ToBoolean() -> bool {
        switch Type {
        case .undefined, .null:
            return false
        case .boolean:
            return IntVal != 0
        case .int32:
            return IntVal != 0
        case .number:
            return DoubleVal != 0.0 && !DoubleVal.isNaN
        case .string:
            return !StrVal.isEmpty
        case .object, .symbol:
            return true
        }
    }

    /// ToNumber implements ECMA-262 §7.1.3.
    public func ToNumber() -> float64 {
        switch Type {
        case .undefined:
            return float64.nan
        case .null:
            return 0.0
        case .boolean:
            return IntVal != 0 ? 1.0 : 0.0
        case .int32:
            return float64(IntVal)
        case .number:
            return DoubleVal
        case .string:
            if StrVal.isEmpty { return 0.0 }
            return float64(StrVal) ?? float64.nan
        case .object, .symbol:
            return float64.nan
        }
    }

    /// ToInt32 implements ECMA-262 §7.1.6.
    public func ToInt32() -> int32 {
        if Type == .int32 { return IntVal }
        let num = ToNumber()
        if num.isNaN || num.isInfinite || num == 0.0 {
            return 0
        }
        let int64Val = int64(num)
        return int32(truncatingIfNeeded: int64Val)
    }

    /// ToUint32 implements ECMA-262 §7.1.7.
    public func ToUint32() -> uint32 {
        return uint32(bitPattern: ToInt32())
    }

    /// ToString implements ECMA-262 §7.1.17.
    public func ToString() -> string {
        switch Type {
        case .undefined:
            return "undefined"
        case .null:
            return "null"
        case .boolean:
            return IntVal != 0 ? "true" : "false"
        case .int32:
            return "\(IntVal)"
        case .number:
            if DoubleVal.isNaN { return "NaN" }
            if DoubleVal.isInfinite { return DoubleVal > 0 ? "Infinity" : "-Infinity" }
            if DoubleVal == 0.0 { return "0" }
            if DoubleVal == float64(int64(DoubleVal)) {
                return "\(int64(DoubleVal))"
            }
            return "\(DoubleVal)"
        case .string:
            return StrVal
        case .object:
            return "[object Object]"
        case .symbol:
            return "Symbol()"
        }
    }

    public var description: string {
        return ToString()
    }

    public static func ==(lhs: Value, rhs: Value) -> bool {
        return StrictEquals(lhs, rhs)
    }
}

/// StrictEquals implements ECMA-262 §7.2.14 (===).
public func StrictEquals(_ x: Value, _ y: Value) -> bool {
    if x.Type != y.Type {
        // Exception: int32 and number comparison
        if x.IsNumber && y.IsNumber {
            return x.ToNumber() == y.ToNumber()
        }
        return false
    }
    switch x.Type {
    case .undefined, .null:
        return true
    case .boolean:
        return x.IntVal == y.IntVal
    case .int32:
        return x.IntVal == y.IntVal
    case .number:
        return x.DoubleVal == y.DoubleVal
    case .string:
        return x.StrVal == y.StrVal
    case .object:
        return x.ObjVal === y.ObjVal
    case .symbol:
        return x.ObjVal === y.ObjVal
    }
}

/// AbstractEquals implements ECMA-262 §7.2.13 (==).
public func AbstractEquals(_ x: Value, _ y: Value) -> bool {
    if x.Type == y.Type {
        return StrictEquals(x, y)
    }
    if (x.IsNull && y.IsUndefined) || (x.IsUndefined && y.IsNull) {
        return true
    }
    if x.IsNumber && y.IsString {
        return x.ToNumber() == y.ToNumber()
    }
    if x.IsString && y.IsNumber {
        return x.ToNumber() == y.ToNumber()
    }
    if x.IsBoolean {
        return AbstractEquals(Value.Number(x.ToNumber()), y)
    }
    if y.IsBoolean {
        return AbstractEquals(x, Value.Number(y.ToNumber()))
    }
    return false
}
