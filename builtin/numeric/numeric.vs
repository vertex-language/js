package numeric

import (
    "js/object"
    "js/value"
)

/// Register registers Number and Math built-ins (§21) into the realm.
public func Register(into realm: object.Realm) {
    let g = realm.GlobalObject

    // Number constructor
    let numberCtor = realm.NewFunction(name: "Number") { _, _, args in
        let n = args.isEmpty ? 0.0 : args[0].ToNumber()
        return value.Value.Number(n)
    }
    numberCtor.Set("MAX_SAFE_INTEGER", value.Value.Number(9007199254740991.0))
    numberCtor.Set("MIN_SAFE_INTEGER", value.Value.Number(-9007199254740991.0))
    numberCtor.Set("EPSILON", value.Value.Number(2.220446049250313e-16))
    numberCtor.Set("NaN", value.Value.Number(float64.nan))
    numberCtor.Set("POSITIVE_INFINITY", value.Value.Number(float64.infinity))
    numberCtor.Set("NEGATIVE_INFINITY", value.Value.Number(-float64.infinity))

    let isNaNFn = realm.NewFunction(name: "isNaN") { _, _, args in
        if args.isEmpty { return value.Value.False }
        let arg = args[0]
        if !arg.IsNumber { return value.Value.False }
        return value.Value.Boolean(arg.ToNumber().isNaN)
    }
    numberCtor.Set("isNaN", value.Value.Object(isNaNFn))

    let isIntegerFn = realm.NewFunction(name: "isInteger") { _, _, args in
        if args.isEmpty { return value.Value.False }
        let arg = args[0]
        if !arg.IsNumber { return value.Value.False }
        let d = arg.ToNumber()
        if d.isNaN || d.isInfinite { return value.Value.False }
        return value.Value.Boolean(float64(int64(d)) == d)
    }
    numberCtor.Set("isInteger", value.Value.Object(isIntegerFn))

    g.Set("Number", value.Value.Object(numberCtor))

    // Math object
    let mathObj = realm.NewObject()
    mathObj.InternalTag = "Math"
    mathObj.Set("PI", value.Value.Number(3.141592653589793))
    mathObj.Set("E", value.Value.Number(2.718281828459045))
    mathObj.Set("LN2", value.Value.Number(0.6931471805599453))
    mathObj.Set("LN10", value.Value.Number(2.302585092994046))
    mathObj.Set("SQRT2", value.Value.Number(1.4142135623730951))

    mathObj.Set("abs", value.Value.Object(realm.NewFunction(name: "abs") { _, _, args in
        let n = args.isEmpty ? float64.nan : args[0].ToNumber()
        return value.Value.Number(n < 0 ? -n : n)
    }))

    mathObj.Set("floor", value.Value.Object(realm.NewFunction(name: "floor") { _, _, args in
        let n = args.isEmpty ? float64.nan : args[0].ToNumber()
        if n.isNaN || n.isInfinite { return value.Value.Number(n) }
        var i = int64(n)
        if float64(i) > n { i -= 1 }
        return value.Value.Number(float64(i))
    }))

    mathObj.Set("ceil", value.Value.Object(realm.NewFunction(name: "ceil") { _, _, args in
        let n = args.isEmpty ? float64.nan : args[0].ToNumber()
        if n.isNaN || n.isInfinite { return value.Value.Number(n) }
        var i = int64(n)
        if float64(i) < n { i += 1 }
        return value.Value.Number(float64(i))
    }))

    mathObj.Set("round", value.Value.Object(realm.NewFunction(name: "round") { _, _, args in
        let n = args.isEmpty ? float64.nan : args[0].ToNumber()
        if n.isNaN || n.isInfinite { return value.Value.Number(n) }
        let rounded = int64(n >= 0 ? n + 0.5 : n - 0.5)
        return value.Value.Number(float64(rounded))
    }))

    mathObj.Set("min", value.Value.Object(realm.NewFunction(name: "min") { _, _, args in
        if args.isEmpty { return value.Value.Number(float64.infinity) }
        var minVal = args[0].ToNumber()
        for i in 1..<args.count {
            let v = args[i].ToNumber()
            if v.isNaN { return value.Value.Number(float64.nan) }
            if v < minVal { minVal = v }
        }
        return value.Value.Number(minVal)
    }))

    mathObj.Set("max", value.Value.Object(realm.NewFunction(name: "max") { _, _, args in
        if args.isEmpty { return value.Value.Number(-float64.infinity) }
        var maxVal = args[0].ToNumber()
        for i in 1..<args.count {
            let v = args[i].ToNumber()
            if v.isNaN { return value.Value.Number(float64.nan) }
            if v > maxVal { maxVal = v }
        }
        return value.Value.Number(maxVal)
    }))

    mathObj.Set("sqrt", value.Value.Object(realm.NewFunction(name: "sqrt") { _, _, args in
        let n = args.isEmpty ? float64.nan : args[0].ToNumber()
        if n < 0 { return value.Value.Number(float64.nan) }
        if n == 0 { return value.Value.Number(0.0) }
        // Simple Newton-Raphson approximation
        var x = n / 2.0
        for _ in 0..<20 {
            x = 0.5 * (x + n / x)
        }
        return value.Value.Number(x)
    }))

    g.Set("Math", value.Value.Object(mathObj))
}
