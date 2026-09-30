// Package numeric installs the numbers and dates (ECMA-262 §21):
// Number, BigInt, Math and Date.
package numeric

import (
    "js/object"
    "js/str"
    "js/value"
    "math"
    "math/rand"
    "time"
)

typealias Value = object.Value

func key(_ s: string) -> value.PropertyKey { return value.PropertyKey.Named(s) }

/// Install defines Number, BigInt, Math and Date.
public func Install(_ r: object.Realm) {
    installNumber(r)
    installBigInt(r)
    installMath(r)
    installDate(r)
}

// MARK: Number (§21.1)

func thisNumber(_ v: Value, _ method: string) throws -> float64 {
    if case .number(let d) = v { return d }
    if case .object(let o) = v, o.Kind == .number, case .number(let d) = o.PrimitiveValue { return d }
    throw object.ThrowTypeError("Number.prototype.\(method) requires that 'this' be a Number")
}

func installNumber(_ r: object.Realm) {
    let np = r.NumberPrototype
    np.Kind = .number
    np.PrimitiveValue = .number(0)
    let ctor = r.Constructor("Number", 1, prototype: np) { _, args, nt in
        var n: float64 = 0
        if args.count > 0 {
            let prim = try object.ToNumeric(args[0])
            if case .bigint(let b) = prim { n = b.ToDouble() } else if case .number(let d) = prim { n = d }
        }
        guard let t = nt else { return .number(n) }
        let o = try object.OrdinaryCreateFromConstructor(t, r.NumberPrototype)
        o.Kind = .number
        o.PrimitiveValue = .number(n)
        return .object(o)
    }
    let consts: [(string, float64)] = [
        ("EPSILON", 2.220446049250313e-16), ("MAX_SAFE_INTEGER", 9007199254740991),
        ("MAX_VALUE", 1.7976931348623157e308), ("MIN_SAFE_INTEGER", -9007199254740991),
        ("MIN_VALUE", 5e-324), ("NaN", float64.nan),
        ("NEGATIVE_INFINITY", -float64.infinity), ("POSITIVE_INFINITY", float64.infinity),
    ]
    for (n, v) in consts {
        ctor.DefineData(key(n), .number(v), writable: false, enumerable: false, configurable: false)
    }
    r.Method(ctor, "isFinite", 1) { _, args, _ in
        if case .number(let d) = object.Arg(args, 0) { return .bool(d.isFinite) }
        return .bool(false)
    }
    r.Method(ctor, "isNaN", 1) { _, args, _ in
        if case .number(let d) = object.Arg(args, 0) { return .bool(d.isNaN) }
        return .bool(false)
    }
    r.Method(ctor, "isInteger", 1) { _, args, _ in
        if case .number(let d) = object.Arg(args, 0) { return .bool(value.IsIntegral(d)) }
        return .bool(false)
    }
    r.Method(ctor, "isSafeInteger", 1) { _, args, _ in
        if case .number(let d) = object.Arg(args, 0) {
            return .bool(value.IsIntegral(d) && math.Abs(d) <= 9007199254740991)
        }
        return .bool(false)
    }
    if let pf = r.Intrinsics["parseFloat"] {
        ctor.DefineData(key("parseFloat"), .object(pf), writable: true, enumerable: false, configurable: true)
    }
    if let pi = r.Intrinsics["parseInt"] {
        ctor.DefineData(key("parseInt"), .object(pi), writable: true, enumerable: false, configurable: true)
    }

    r.Method(np, "toString", 1) { thisV, args, _ in
        let x = try thisNumber(thisV, "toString")
        let rv = object.Arg(args, 0)
        var radix: float64 = 10
        if !rv.IsUndefined { radix = try object.ToIntegerOrInfinity(rv) }
        if radix < 2 || radix > 36 { throw object.ThrowRangeError("toString() radix must be between 2 and 36") }
        if radix == 10 { return .string(value.NumberToJSString(x)) }
        return .string(str.JSString.From(value.NumberToRadixString(x, int(radix))))
    }
    r.Method(np, "toLocaleString", 0) { thisV, _, _ in
        return .string(str.JSString.From(LocaleString(try thisNumber(thisV, "toLocaleString"))))
    }
    r.Method(np, "valueOf", 0) { thisV, _, _ in
        return .number(try thisNumber(thisV, "valueOf"))
    }
    r.Method(np, "toFixed", 1) { thisV, args, _ in
        let x = try thisNumber(thisV, "toFixed")
        let f = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        if !f.isFinite || f < 0 || f > 100 { throw object.ThrowRangeError("toFixed() digits argument must be between 0 and 100") }
        if !x.isFinite || math.Abs(x) >= 1e21 { return .string(value.NumberToJSString(x)) }
        return .string(str.JSString.From(value.ToFixed(x, int(f))))
    }
    r.Method(np, "toExponential", 1) { thisV, args, _ in
        let x = try thisNumber(thisV, "toExponential")
        let fv = object.Arg(args, 0)
        let f = try object.ToIntegerOrInfinity(fv)
        if !x.isFinite { return .string(value.NumberToJSString(x)) }
        if !f.isFinite || f < 0 || f > 100 { throw object.ThrowRangeError("toExponential() argument must be between 0 and 100") }
        return .string(str.JSString.From(value.ToExponential(x, fv.IsUndefined ? -1 : int(f))))
    }
    r.Method(np, "toPrecision", 1) { thisV, args, _ in
        let x = try thisNumber(thisV, "toPrecision")
        let pv = object.Arg(args, 0)
        if pv.IsUndefined { return .string(value.NumberToJSString(x)) }
        let p = try object.ToIntegerOrInfinity(pv)
        if !x.isFinite { return .string(value.NumberToJSString(x)) }
        if !p.isFinite || p < 1 || p > 100 { throw object.ThrowRangeError("toPrecision() argument must be between 1 and 100") }
        return .string(str.JSString.From(value.ToPrecision(x, int(p))))
    }
}

/// LocaleString is toLocaleString in en-US: grouped thousands and at
/// most three fraction digits, as ICU formats it.
public func LocaleString(_ x: float64) -> string {
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x < 0 ? "-∞" : "∞" }
    let neg = x < 0
    var s = value.ToFixed(math.Abs(x), 3)
    if math.Abs(x) >= 1e21 { s = value.NumberToString(math.Abs(x)) }
    var intPart = s
    var frac = ""
    if let dot = s.firstIndex(of: ".") {
        intPart = string(s[s.startIndex..<dot])
        frac = string(s[s.index(after: dot)...])
        while frac.hasSuffix("0") { frac = string(frac.prefix(frac.count - 1)) }
    }
    var grouped = ""
    var count = 0
    for c in intPart.reversed() {
        if count > 0 && count % 3 == 0 { grouped = "," + grouped }
        grouped = string(c) + grouped
        count += 1
    }
    var out = neg ? "-" + grouped : grouped
    if !frac.isEmpty { out += "." + frac }
    return out
}

// MARK: BigInt (§21.2)

func thisBigInt(_ v: Value, _ method: string) throws -> value.BigInt {
    if case .bigint(let b) = v { return b }
    if case .object(let o) = v, o.Kind == .bigint, case .bigint(let b) = o.PrimitiveValue { return b }
    throw object.ThrowTypeError("BigInt.prototype.\(method) requires that 'this' be a BigInt")
}

func installBigInt(_ r: object.Realm) {
    let bp = r.BigIntPrototype
    let ctor = r.Constructor("BigInt", 1, prototype: bp) { _, args, nt in
        if nt != nil { throw object.ThrowTypeError("BigInt is not a constructor") }
        let prim = try object.ToPrimitive(object.Arg(args, 0), .number)
        if case .number(let d) = prim {
            if !value.IsIntegral(d) {
                throw object.ThrowRangeError("The number \(value.NumberToString(d)) cannot be converted to a BigInt because it is not an integer")
            }
            return .bigint(value.BigInt.FromDouble(d))
        }
        return .bigint(try object.ToBigInt(prim))
    }
    r.Method(ctor, "asIntN", 2) { _, args, _ in
        let bits = try object.ToIndex(object.Arg(args, 0))
        let b = try object.ToBigInt(object.Arg(args, 1))
        return .bigint(value.BigInt.AsIntN(bits, b))
    }
    r.Method(ctor, "asUintN", 2) { _, args, _ in
        let bits = try object.ToIndex(object.Arg(args, 0))
        let b = try object.ToBigInt(object.Arg(args, 1))
        return .bigint(value.BigInt.AsUintN(bits, b))
    }
    r.Method(bp, "toString", 0) { thisV, args, _ in
        let b = try thisBigInt(thisV, "toString")
        let rv = object.Arg(args, 0)
        var radix: float64 = 10
        if !rv.IsUndefined { radix = try object.ToIntegerOrInfinity(rv) }
        if radix < 2 || radix > 36 { throw object.ThrowRangeError("toString() radix must be between 2 and 36") }
        return .string(str.JSString.From(b.ToString(int(radix))))
    }
    r.Method(bp, "toLocaleString", 0) { thisV, _, _ in
        let s = try thisBigInt(thisV, "toLocaleString").ToString(10)
        var digits = s
        var neg = false
        if digits.hasPrefix("-") { neg = true; digits = string(digits.suffix(digits.count - 1)) }
        var grouped = ""
        var count = 0
        for c in digits.reversed() {
            if count > 0 && count % 3 == 0 { grouped = "," + grouped }
            grouped = string(c) + grouped
            count += 1
        }
        return .string(str.JSString.From(neg ? "-" + grouped : grouped))
    }
    r.Method(bp, "valueOf", 0) { thisV, _, _ in
        return .bigint(try thisBigInt(thisV, "valueOf"))
    }
    bp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("BigInt")), writable: false, enumerable: false, configurable: true)
}

// MARK: Math (§21.3)

/// generator is Math.random's: xorshift128+, as V8's.
var generator = rand.Xorshift128Plus(seed: uint64(bitPattern: time.Timestamp.Now().AsUnixMilliseconds()) &* 0x9E3779B97F4A7C15)

func installMath(_ r: object.Realm) {
    let m = object.JSObject(proto: r.ObjectPrototype)
    r.DefineGlobal("Math", .object(m))
    let consts: [(string, float64)] = [
        ("E", math.E), ("LN10", 2.302585092994046), ("LN2", 0.6931471805599453),
        ("LOG10E", 0.4342944819032518), ("LOG2E", 1.4426950408889634), ("PI", math.Pi),
        ("SQRT1_2", 0.7071067811865476), ("SQRT2", 1.4142135623730951),
    ]
    for (n, v) in consts {
        m.DefineData(key(n), .number(v), writable: false, enumerable: false, configurable: false)
    }
    m.DefineData(.symbol(value.SymToStringTag), .string(str.Name("Math")), writable: false, enumerable: false, configurable: true)

    let unary: [(string, (float64) -> float64)] = [
        ("abs", { x in return math.Abs(x) }), ("acos", { x in return math.Acos(x) }), ("acosh", { x in return math.Acosh(x) }), ("asin", { x in return math.Asin(x) }),
        ("asinh", { x in return math.Asinh(x) }), ("atan", { x in return math.Atan(x) }), ("atanh", { x in return math.Atanh(x) }), ("cbrt", { x in return math.Cbrt(x) }),
        ("ceil", { x in return math.Ceil(x) }), ("cos", { x in return math.Cos(x) }), ("cosh", { x in return math.Cosh(x) }), ("exp", { x in return math.Exp(x) }),
        ("expm1", { x in return math.Expm1(x) }), ("floor", { x in return math.Floor(x) }), ("log", { x in return math.Log(x) }), ("log1p", { x in return math.Log1p(x) }),
        ("log10", { x in return math.Log10(x) }), ("log2", { x in return math.Log2(x) }), ("sin", { x in return math.Sin(x) }), ("sinh", { x in return math.Sinh(x) }),
        ("sqrt", { x in return math.Sqrt(x) }), ("tan", { x in return math.Tan(x) }), ("tanh", { x in return math.Tanh(x) }), ("trunc", { x in return math.Trunc(x) }),
        ("fround", { x in return float64(float32(x)) }),
        ("f16round", { x in return float64(float16(x)) }),
        ("sign", { x in
            if x.isNaN || x == 0 { return x }
            return x > 0 ? 1 : -1
        }),
        ("round", { x in
            // Round half up toward +∞, keeping -0 and values in [-0.5, 0).
            if !x.isFinite || x == 0 { return x }
            if x > 0 && x < 0.5 { return 0 }
            if x < 0 && x >= -0.5 { return -0.0 }
            let f = math.Floor(x)
            return x - f >= 0.5 ? f + 1 : f
        }),
        ("clz32", { x in
            let n = value.DoubleToUint32(x)
            return float64(n == 0 ? 32 : n.leadingZeroBitCount)
        }),
    ]
    for (n, f) in unary {
        r.Method(m, n, 1) { _, args, _ in
            return .number(f(try object.ToNumber(object.Arg(args, 0))))
        }
    }
    r.Method(m, "atan2", 2) { _, args, _ in
        let y = try object.ToNumber(object.Arg(args, 0))
        let x = try object.ToNumber(object.Arg(args, 1))
        return .number(math.Atan2(y, x))
    }
    r.Method(m, "pow", 2) { _, args, _ in
        let b = try object.ToNumber(object.Arg(args, 0))
        let e = try object.ToNumber(object.Arg(args, 1))
        return .number(object.NumberPow(b, e))
    }
    r.Method(m, "imul", 2) { _, args, _ in
        let a = try object.ToInt32(object.Arg(args, 0))
        let b = try object.ToInt32(object.Arg(args, 1))
        return .number(float64(a &* b))
    }
    r.Method(m, "max", 2) { _, args, _ in
        var nums: [float64] = []
        for a in args { nums.append(try object.ToNumber(a)) }
        var out = -float64.infinity
        for n in nums {
            if n.isNaN { return .number(float64.nan) }
            if n > out || (n == 0 && out == 0 && out.sign == .minus) { out = n }
        }
        return .number(out)
    }
    r.Method(m, "min", 2) { _, args, _ in
        var nums: [float64] = []
        for a in args { nums.append(try object.ToNumber(a)) }
        var out = float64.infinity
        for n in nums {
            if n.isNaN { return .number(float64.nan) }
            if n < out || (n == 0 && out == 0 && n.sign == .minus) { out = n }
        }
        return .number(out)
    }
    r.Method(m, "hypot", 2) { _, args, _ in
        var nums: [float64] = []
        for a in args { nums.append(try object.ToNumber(a)) }
        return .number(Hypot(nums))
    }
    r.Method(m, "sumPrecise", 1) { _, args, _ in
        let items = object.Arg(args, 0)
        try object.RequireObjectCoercible(items)
        let rec = try object.GetIterator(items)
        var nums: [float64] = []
        while let v = try object.IteratorStepValue(rec) {
            guard case .number(let d) = v else {
                object.IteratorCloseOnThrow(rec)
                throw object.ThrowTypeError("Math.sumPrecise requires an iterable of numbers")
            }
            nums.append(d)
        }
        return .number(SumPrecise(nums))
    }
    r.Method(m, "random", 0) { _, _, _ in
        return .number(generator.Float64())
    }
}

/// Hypot is Math.hypot as V8 computes it: scale by the largest magnitude
/// and sum the squares with Kahan compensation.
public func Hypot(_ xs: [float64]) -> float64 {
    var maxv: float64 = 0
    var sawNaN = false
    for x in xs {
        let a = math.Abs(x)
        if a.isInfinite { return float64.infinity }
        if a.isNaN { sawNaN = true }
        if a > maxv { maxv = a }
    }
    if sawNaN { return float64.nan }
    if maxv == 0 { return 0 }
    var sum: float64 = 0
    var compensation: float64 = 0
    for x in xs {
        let n = math.Abs(x) / maxv
        let summand = n * n - compensation
        let preliminary = sum + summand
        compensation = (preliminary - sum) - summand
        sum = preliminary
    }
    return math.Sqrt(sum) * maxv
}

/// SumPrecise is Math.sumPrecise (§21.3.2.34): the exact sum rounded once,
/// by Shewchuk's partials.
public func SumPrecise(_ xs: [float64]) -> float64 {
    var partials: [float64] = []
    var special: float64 = 0
    var sawPosInf = false
    var sawNegInf = false
    var allNegZero = true
    for x in xs {
        if x.isNaN { special = float64.nan }
        if x == float64.infinity { sawPosInf = true }
        if x == -float64.infinity { sawNegInf = true }
        if !(x == 0 && x.sign == .minus) { allNegZero = false }
        if !x.isFinite { continue }
        var v = x
        var i = 0
        var j = 0
        while j < partials.count {
            var y = partials[j]
            if math.Abs(v) < math.Abs(y) { let t = v; v = y; y = t }
            let hi = v + y
            let lo = y - (hi - v)
            if lo != 0 {
                partials[i] = lo
                i += 1
            }
            v = hi
            j += 1
        }
        while partials.count > i { partials.removeLast() }
        partials.append(v)
    }
    if special.isNaN || (sawPosInf && sawNegInf) { return float64.nan }
    if sawPosInf { return float64.infinity }
    if sawNegInf { return -float64.infinity }
    if xs.isEmpty || allNegZero { return -0.0 }
    // Add the partials from the top, correcting the last rounding.
    var n = partials.count
    if n == 0 { return 0 }
    n -= 1
    var hi = partials[n]
    var lo: float64 = 0
    while n > 0 {
        let x = hi
        n -= 1
        let y = partials[n]
        hi = x + y
        let yr = hi - x
        lo = y - yr
        if lo != 0 { break }
    }
    if n > 0 && ((lo < 0 && partials[n - 1] < 0) || (lo > 0 && partials[n - 1] > 0)) {
        let y = lo * 2
        let x = hi + y
        let yr = x - hi
        if y == yr { hi = x }
    }
    return hi
}
