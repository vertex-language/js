// Package indexed installs the indexed collections' Array (ECMA-262
// §23.1) and %ArrayIteratorPrototype%. Typed arrays live in structured.
package indexed

import (
    "js/object"
    "js/str"
    "js/value"
)

typealias Value = object.Value

func key(_ s: string) -> value.PropertyKey { return value.PropertyKey.Named(s) }
func idx(_ i: int) -> value.PropertyKey { return value.PropertyKey.FromNumber(float64(i)) }

/// TypedArrayLength is set by the structured package: a typed array's
/// length for the array iterator, which throws when it is out of bounds.
public var TypedArrayLength: ((object.JSObject) throws -> int)? = nil

// MARK: element access

/// get is Get(o, ToString(i)), reading a dense array's element directly.
func get(_ o: object.JSObject, _ i: int) throws -> Value {
    if let a = o as? object.ArrayObject, !a.Sparse, i < a.Dense.count {
        let v = a.Dense[i]
        if !v.IsEmpty { return v }
    }
    return try o.Get(idx(i), .object(o))
}

func has(_ o: object.JSObject, _ i: int) throws -> bool {
    if let a = o as? object.ArrayObject, !a.Sparse, i < a.Dense.count, !a.Dense[i].IsEmpty {
        return true
    }
    return try o.HasProperty(idx(i))
}

func set(_ o: object.JSObject, _ i: int, _ v: Value) throws {
    try object.SetProperty(o, idx(i), v, throwing: true)
}

func setLength(_ o: object.JSObject, _ n: int) throws {
    try object.SetProperty(o, key("length"), .number(float64(n)), throwing: true)
}

func delete(_ o: object.JSObject, _ i: int) throws {
    try object.DeletePropertyOrThrow(o, idx(i))
}

func callable(_ v: Value) throws -> Value {
    if !v.IsCallable { throw object.ThrowTypeError("\(object.Describe(v)) is not a function") }
    return v
}

/// relative clamps a relative index argument into [0, len].
func relative(_ v: Value, _ len: int, _ dflt: int) throws -> int {
    if v.IsUndefined { return dflt }
    let r = try object.ToIntegerOrInfinity(v)
    if r < 0 {
        let x = float64(len) + r
        return x < 0 ? 0 : int(x)
    }
    return r > float64(len) ? len : int(r)
}

func thisObject(_ v: Value) throws -> (object.JSObject, int) {
    let o = try object.ToObject(v)
    return (o, try object.LengthOfArrayLike(o))
}

func checkLength(_ n: float64) throws {
    if n > 9007199254740991 { throw object.ThrowTypeError("Invalid array length") }
}

// MARK: install

/// Install defines Array and %ArrayIteratorPrototype%.
public func Install(_ r: object.Realm) {
    let ap = r.ArrayPrototype
    let ctor = r.Constructor("Array", 1, prototype: ap) { _, args, nt in
        let proto = try object.GetPrototypeFromConstructor(nt ?? r.ArrayConstructor!, r.ArrayPrototype)
        if args.count == 0 { return .object(try object.ArrayCreate(0, proto: proto)) }
        if args.count == 1 {
            let len = args[0]
            guard case .number(let d) = len else {
                let a = try object.ArrayCreate(0, proto: proto)
                a.Dense = [len]
                a.Length = 1
                return .object(a)
            }
            let n = value.DoubleToUint32(d)
            if float64(n) != d { throw object.ThrowRangeError("Invalid array length") }
            return .object(try object.ArrayCreate(d, proto: proto))
        }
        let a = try object.ArrayCreate(0, proto: proto)
        a.Dense = args
        a.Length = uint32(args.count)
        return .object(a)
    }
    r.ArrayConstructor = ctor
    r.Getter(ctor, .symbol(value.SymSpecies)) { thisV, _, _ in return thisV }

    r.Method(ctor, "isArray", 1) { _, args, _ in
        return .bool(try object.IsArray(object.Arg(args, 0)))
    }
    r.Method(ctor, "of", 0) { thisV, args, _ in
        let a = try construct(thisV, args.count)
        var k = 0
        while k < args.count {
            try object.CreateDataPropertyOrThrow(a, idx(k), args[k])
            k += 1
        }
        try setLength(a, args.count)
        return .object(a)
    }
    installFromAsync(r, ctor)
    r.Method(ctor, "from", 1) { thisV, args, _ in
        let items = object.Arg(args, 0)
        let mapFn = object.Arg(args, 1)
        let thisArg = object.Arg(args, 2)
        let mapping = !mapFn.IsUndefined
        if mapping { _ = try callable(mapFn) }
        let using = try object.GetMethod(items, .symbol(value.SymIterator))
        if !using.IsUndefined {
            let a = try construct(thisV, -1)
            let rec = try object.GetIteratorFromMethod(items, using)
            var k = 0
            while true {
                guard let next = try object.IteratorStepValue(rec) else {
                    try setLength(a, k)
                    return .object(a)
                }
                do {
                    let v = mapping ? try object.Call(mapFn, thisArg, [next, .number(float64(k))]) : next
                    try object.CreateDataPropertyOrThrow(a, idx(k), v)
                } catch {
                    object.IteratorCloseOnThrow(rec)
                    throw error
                }
                k += 1
            }
        }
        let src = try object.ToObject(items)
        let len = try object.LengthOfArrayLike(src)
        let a = try construct(thisV, len)
        var k = 0
        while k < len {
            let kv = try get(src, k)
            let v = mapping ? try object.Call(mapFn, thisArg, [kv, .number(float64(k))]) : kv
            try object.CreateDataPropertyOrThrow(a, idx(k), v)
            k += 1
        }
        try setLength(a, len)
        return .object(a)
    }

    installAccessors(r, ap)
    installIterationMethods(r, ap)
    installMutators(r, ap)
    installCopying(r, ap)
    installIterators(r, ap)

    let unscopables = object.JSObject(proto: nil)
    for n in ["at", "copyWithin", "entries", "fill", "find", "findIndex", "findLast", "findLastIndex", "flat", "flatMap", "includes", "keys", "toReversed", "toSorted", "toSpliced", "values"] {
        unscopables.DefineData(key(n), .bool(true))
    }
    ap.DefineData(.symbol(value.SymUnscopables), .object(unscopables), writable: false, enumerable: false, configurable: true)
}

/// construct makes `new C(len)` for Array.of and Array.from, or a plain
/// array when this is not a constructor. A len of -1 passes no argument.
func construct(_ c: Value, _ len: int) throws -> object.JSObject {
    if case .object(let co) = c, co.IsConstructor {
        let args: [Value] = len < 0 ? [] : [.number(float64(len))]
        let v = try object.Construct(co, args)
        guard case .object(let o) = v else { throw object.ThrowTypeError("constructor did not return an object") }
        return o
    }
    return try object.ArrayCreate(len < 0 ? 0 : float64(len))
}

// MARK: reading

func installAccessors(_ r: object.Realm, _ ap: object.JSObject) {
    r.Method(ap, "at", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let rel = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        let k = rel >= 0 ? rel : float64(len) + rel
        if k < 0 || k >= float64(len) { return .undefined }
        return try get(o, int(k))
    }
    r.Method(ap, "indexOf", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        if len == 0 { return .number(-1) }
        var n = try object.ToIntegerOrInfinity(object.Arg(args, 1))
        if n >= float64(len) { return .number(-1) }
        if n < 0 { n = float64(len) + n; if n < 0 { n = 0 } }
        let target = object.Arg(args, 0)
        var k = int(n)
        while k < len {
            if try has(o, k) {
                if object.StrictEquals(try get(o, k), target) { return .number(float64(k)) }
            }
            k += 1
        }
        return .number(-1)
    }
    r.Method(ap, "lastIndexOf", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        if len == 0 { return .number(-1) }
        var n = args.count > 1 ? try object.ToIntegerOrInfinity(args[1]) : float64(len - 1)
        if n == -float64.infinity { return .number(-1) }
        if n >= 0 { if n > float64(len - 1) { n = float64(len - 1) } } else { n = float64(len) + n }
        let target = object.Arg(args, 0)
        var k = int(n)
        while k >= 0 {
            if try has(o, k) {
                if object.StrictEquals(try get(o, k), target) { return .number(float64(k)) }
            }
            k -= 1
        }
        return .number(-1)
    }
    r.Method(ap, "includes", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        if len == 0 { return .bool(false) }
        var n = try object.ToIntegerOrInfinity(object.Arg(args, 1))
        if n >= float64(len) { return .bool(false) }
        if n < 0 { n = float64(len) + n; if n < 0 { n = 0 } }
        let target = object.Arg(args, 0)
        var k = int(n)
        while k < len {
            if object.SameValueZero(try get(o, k), target) { return .bool(true) }
            k += 1
        }
        return .bool(false)
    }
    r.Method(ap, "join", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let sepV = object.Arg(args, 0)
        let sep = sepV.IsUndefined ? str.Name(",") : try object.ToString(sepV)
        return .string(try join(o, len, sep, locale: false))
    }
    r.Method(ap, "toString", 0) { thisV, _, _ in
        let o = try object.ToObject(thisV)
        let f = try o.Get(key("join"), .object(o))
        if f.IsCallable { return try object.Call(f, .object(o), []) }
        return try object.Call(.object(r.Intrinsics["ObjectToString"]!), .object(o), [])
    }
    r.Method(ap, "toLocaleString", 0) { thisV, _, _ in
        let (o, len) = try thisObject(thisV)
        return .string(try join(o, len, str.Name(","), locale: true))
    }
    if let ots = r.ObjectPrototype.OwnSlot(key("toString")), case .object(let f) = ots.Value {
        r.Intrinsics["ObjectToString"] = f
    }
}

/// joining is the arrays being joined, so a cycle joins as "".
var joining: [object.JSObject] = []

func join(_ o: object.JSObject, _ len: int, _ sep: str.JSString, locale: bool) throws -> str.JSString {
    for j in joining where j === o { return str.JSString.Empty }
    joining.append(o)
    defer { joining.removeLast() }
    var b = str.Builder()
    var k = 0
    while k < len {
        if k > 0 { b.Append(sep) }
        let el = try get(o, k)
        if !el.IsNullish {
            if locale {
                b.Append(try object.ToString(try object.Invoke(el, key("toLocaleString"), [])))
            } else {
                b.Append(try object.ToString(el))
            }
        }
        k += 1
    }
    return b.Build()
}

// MARK: iteration methods

func installIterationMethods(_ r: object.Realm, _ ap: object.JSObject) {
    r.Method(ap, "forEach", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        let t = object.Arg(args, 1)
        var k = 0
        while k < len {
            if try has(o, k) {
                _ = try object.Call(cb, t, [try get(o, k), .number(float64(k)), .object(o)])
            }
            k += 1
        }
        return .undefined
    }
    r.Method(ap, "map", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        let t = object.Arg(args, 1)
        let a = try object.ArraySpeciesCreate(o, float64(len))
        var k = 0
        while k < len {
            if try has(o, k) {
                let v = try object.Call(cb, t, [try get(o, k), .number(float64(k)), .object(o)])
                try object.CreateDataPropertyOrThrow(a, idx(k), v)
            }
            k += 1
        }
        return .object(a)
    }
    r.Method(ap, "filter", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        let t = object.Arg(args, 1)
        let a = try object.ArraySpeciesCreate(o, 0)
        var k = 0
        var to = 0
        while k < len {
            if try has(o, k) {
                let v = try get(o, k)
                if try object.Call(cb, t, [v, .number(float64(k)), .object(o)]).Truthy {
                    try object.CreateDataPropertyOrThrow(a, idx(to), v)
                    to += 1
                }
            }
            k += 1
        }
        return .object(a)
    }
    r.Method(ap, "every", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        let t = object.Arg(args, 1)
        var k = 0
        while k < len {
            if try has(o, k) {
                if !(try object.Call(cb, t, [try get(o, k), .number(float64(k)), .object(o)]).Truthy) { return .bool(false) }
            }
            k += 1
        }
        return .bool(true)
    }
    r.Method(ap, "some", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        let t = object.Arg(args, 1)
        var k = 0
        while k < len {
            if try has(o, k) {
                if try object.Call(cb, t, [try get(o, k), .number(float64(k)), .object(o)]).Truthy { return .bool(true) }
            }
            k += 1
        }
        return .bool(false)
    }
    r.Method(ap, "reduce", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        var k = 0
        var acc: Value = .undefined
        if args.count >= 2 {
            acc = args[1]
        } else {
            var found = false
            while !found && k < len {
                if try has(o, k) {
                    acc = try get(o, k)
                    found = true
                }
                k += 1
            }
            if !found { throw object.ThrowTypeError("Reduce of empty array with no initial value") }
        }
        while k < len {
            if try has(o, k) {
                acc = try object.Call(cb, .undefined, [acc, try get(o, k), .number(float64(k)), .object(o)])
            }
            k += 1
        }
        return acc
    }
    r.Method(ap, "reduceRight", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        var k = len - 1
        var acc: Value = .undefined
        if args.count >= 2 {
            acc = args[1]
        } else {
            var found = false
            while !found && k >= 0 {
                if try has(o, k) {
                    acc = try get(o, k)
                    found = true
                }
                k -= 1
            }
            if !found { throw object.ThrowTypeError("Reduce of empty array with no initial value") }
        }
        while k >= 0 {
            if try has(o, k) {
                acc = try object.Call(cb, .undefined, [acc, try get(o, k), .number(float64(k)), .object(o)])
            }
            k -= 1
        }
        return acc
    }
    r.Method(ap, "find", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        var k = 0
        while k < len {
            let v = try get(o, k)
            if try object.Call(cb, object.Arg(args, 1), [v, .number(float64(k)), .object(o)]).Truthy { return v }
            k += 1
        }
        return .undefined
    }
    r.Method(ap, "findIndex", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        var k = 0
        while k < len {
            if try object.Call(cb, object.Arg(args, 1), [try get(o, k), .number(float64(k)), .object(o)]).Truthy { return .number(float64(k)) }
            k += 1
        }
        return .number(-1)
    }
    r.Method(ap, "findLast", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        var k = len - 1
        while k >= 0 {
            let v = try get(o, k)
            if try object.Call(cb, object.Arg(args, 1), [v, .number(float64(k)), .object(o)]).Truthy { return v }
            k -= 1
        }
        return .undefined
    }
    r.Method(ap, "findLastIndex", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        var k = len - 1
        while k >= 0 {
            if try object.Call(cb, object.Arg(args, 1), [try get(o, k), .number(float64(k)), .object(o)]).Truthy { return .number(float64(k)) }
            k -= 1
        }
        return .number(-1)
    }
    r.Method(ap, "flat", 0) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        var depth: float64 = 1
        if !object.Arg(args, 0).IsUndefined {
            depth = try object.ToIntegerOrInfinity(args[0])
            if depth < 0 { depth = 0 }
        }
        let a = try object.ArraySpeciesCreate(o, 0)
        _ = try flatten(a, o, len, 0, depth, .undefined, .undefined)
        return .object(a)
    }
    r.Method(ap, "flatMap", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let cb = try callable(object.Arg(args, 0))
        let a = try object.ArraySpeciesCreate(o, 0)
        _ = try flatten(a, o, len, 0, 1, cb, object.Arg(args, 1))
        return .object(a)
    }
}

/// flatten is FlattenIntoArray (§23.1.3.13.1).
func flatten(_ target: object.JSObject, _ source: object.JSObject, _ len: int, _ start: int, _ depth: float64, _ mapper: Value, _ thisArg: Value) throws -> int {
    var at = start
    var k = 0
    while k < len {
        if try has(source, k) {
            var el = try get(source, k)
            if !mapper.IsUndefined {
                el = try object.Call(mapper, thisArg, [el, .number(float64(k)), .object(source)])
            }
            var spread = false
            if depth > 0 { spread = try object.IsArray(el) }
            if spread, case .object(let eo) = el {
                let elen = try object.LengthOfArrayLike(eo)
                at = try flatten(target, eo, elen, at, depth - 1, .undefined, .undefined)
            } else {
                if float64(at) >= 9007199254740991 { throw object.ThrowTypeError("Invalid array length") }
                try object.CreateDataPropertyOrThrow(target, idx(at), el)
                at += 1
            }
        }
        k += 1
    }
    return at
}

// MARK: mutators

func installMutators(_ r: object.Realm, _ ap: object.JSObject) {
    r.Method(ap, "push", 1) { thisV, args, _ in
        if case .object(let o) = thisV, let a = o as? object.ArrayObject, a.IsDenseSimple, a.LengthWritable, a.Extensible, int(a.Length) + args.count < 4294967295 {
            for v in args { a.Push(v) }
            return .number(float64(a.Length))
        }
        let (o, len) = try thisObject(thisV)
        try checkLength(float64(len + args.count))
        var n = len
        for v in args {
            try set(o, n, v)
            n += 1
        }
        try setLength(o, n)
        return .number(float64(n))
    }
    r.Method(ap, "pop", 0) { thisV, _, _ in
        let (o, len) = try thisObject(thisV)
        if len == 0 {
            try setLength(o, 0)
            return .undefined
        }
        let v = try get(o, len - 1)
        try delete(o, len - 1)
        try setLength(o, len - 1)
        return v
    }
    r.Method(ap, "shift", 0) { thisV, _, _ in
        let (o, len) = try thisObject(thisV)
        if len == 0 {
            try setLength(o, 0)
            return .undefined
        }
        let first = try get(o, 0)
        if let a = o as? object.ArrayObject, a.IsDenseSimple, a.LengthWritable, !hasHoles(a) {
            a.Dense.removeFirst()
            a.Length -= 1
            return first
        }
        var k = 1
        while k < len {
            if try has(o, k) { try set(o, k - 1, try get(o, k)) } else { try delete(o, k - 1) }
            k += 1
        }
        try delete(o, len - 1)
        try setLength(o, len - 1)
        return first
    }
    r.Method(ap, "unshift", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let n = args.count
        if n > 0 {
            try checkLength(float64(len + n))
            var k = len
            while k > 0 {
                if try has(o, k - 1) { try set(o, k + n - 1, try get(o, k - 1)) } else { try delete(o, k + n - 1) }
                k -= 1
            }
            var j = 0
            while j < n {
                try set(o, j, args[j])
                j += 1
            }
        }
        try setLength(o, len + n)
        return .number(float64(len + n))
    }
    r.Method(ap, "splice", 2) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let start = try relative(object.Arg(args, 0), len, 0)
        var delCount = 0
        var items: [Value] = []
        if args.count == 0 {
            delCount = 0
        } else if args.count == 1 {
            delCount = len - start
        } else {
            let dc = try object.ToIntegerOrInfinity(args[1])
            delCount = dc < 0 ? 0 : (dc > float64(len - start) ? len - start : int(dc))
            var i = 2
            while i < args.count { items.append(args[i]); i += 1 }
        }
        try checkLength(float64(len + items.count - delCount))
        let a = try object.ArraySpeciesCreate(o, float64(delCount))
        var k = 0
        while k < delCount {
            if try has(o, start + k) {
                try object.CreateDataPropertyOrThrow(a, idx(k), try get(o, start + k))
            }
            k += 1
        }
        try setLength(a, delCount)
        let itemCount = items.count
        if itemCount < delCount {
            k = start
            while k < len - delCount {
                if try has(o, k + delCount) { try set(o, k + itemCount, try get(o, k + delCount)) } else { try delete(o, k + itemCount) }
                k += 1
            }
            k = len
            while k > len - delCount + itemCount {
                try delete(o, k - 1)
                k -= 1
            }
        } else if itemCount > delCount {
            k = len - delCount
            while k > start {
                if try has(o, k + delCount - 1) { try set(o, k + itemCount - 1, try get(o, k + delCount - 1)) } else { try delete(o, k + itemCount - 1) }
                k -= 1
            }
        }
        k = 0
        while k < itemCount {
            try set(o, start + k, items[k])
            k += 1
        }
        try setLength(o, len - delCount + itemCount)
        return .object(a)
    }
    r.Method(ap, "reverse", 0) { thisV, _, _ in
        let (o, len) = try thisObject(thisV)
        var lower = 0
        while lower < len / 2 {
            let upper = len - lower - 1
            let le = try has(o, lower)
            let lv = le ? try get(o, lower) : Value.undefined
            let ue = try has(o, upper)
            let uv = ue ? try get(o, upper) : Value.undefined
            if le && ue {
                try set(o, lower, uv)
                try set(o, upper, lv)
            } else if ue {
                try set(o, lower, uv)
                try delete(o, upper)
            } else if le {
                try delete(o, lower)
                try set(o, upper, lv)
            }
            lower += 1
        }
        return .object(o)
    }
    r.Method(ap, "fill", 1) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let k0 = try relative(object.Arg(args, 1), len, 0)
        let end = try relative(object.Arg(args, 2), len, len)
        var k = k0
        while k < end {
            try set(o, k, object.Arg(args, 0))
            k += 1
        }
        return .object(o)
    }
    r.Method(ap, "copyWithin", 2) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        var to = try relative(object.Arg(args, 0), len, 0)
        var from = try relative(object.Arg(args, 1), len, 0)
        let fin = try relative(object.Arg(args, 2), len, len)
        var count = min(fin - from, len - to)
        var dir = 1
        if from < to && to < from + count {
            dir = -1
            from = from + count - 1
            to = to + count - 1
        }
        while count > 0 {
            if try has(o, from) { try set(o, to, try get(o, from)) } else { try delete(o, to) }
            from += dir
            to += dir
            count -= 1
        }
        return .object(o)
    }
    r.Method(ap, "sort", 1) { thisV, args, _ in
        let cmp = object.Arg(args, 0)
        if !cmp.IsUndefined && !cmp.IsCallable {
            throw object.ThrowTypeError("The comparison function must be either a function or undefined")
        }
        let (o, len) = try thisObject(thisV)
        let sorted = try sortValues(try collect(o, len, skipHoles: true), cmp)
        var k = 0
        while k < sorted.count {
            try set(o, k, sorted[k])
            k += 1
        }
        while k < len {
            if try has(o, k) { try delete(o, k) }
            k += 1
        }
        return .object(o)
    }
}

func hasHoles(_ a: object.ArrayObject) -> bool {
    for v in a.Dense where v.IsEmpty { return true }
    return false
}

func collect(_ o: object.JSObject, _ len: int, skipHoles: bool) throws -> [Value] {
    var out: [Value] = []
    var k = 0
    while k < len {
        if !skipHoles || (try has(o, k)) {
            out.append(try get(o, k))
        }
        k += 1
    }
    return out
}

/// sortValues is SortIndexedProperties' ordering: a stable merge sort
/// with undefined last, as V8's TimSort orders a consistent comparator.
public func sortValues(_ items: [Value], _ cmp: Value) throws -> [Value] {
    var vals: [Value] = []
    var undefs = 0
    for v in items {
        if v.IsUndefined { undefs += 1 } else { vals.append(v) }
    }
    // Without a comparator the strings are computed once.
    var keys: [str.JSString] = []
    if cmp.IsUndefined {
        for v in vals { keys.append(try object.ToString(v)) }
    }
    var order: [int] = []
    var i = 0
    while i < vals.count { order.append(i); i += 1 }
    var tmp = order
    var width = 1
    let n = order.count
    while width < n {
        var lo = 0
        while lo < n {
            let mid = min(lo + width, n)
            let hi = min(lo + 2 * width, n)
            var a = lo
            var b = mid
            var t = lo
            while a < mid && b < hi {
                var takeB = false
                if cmp.IsUndefined {
                    takeB = keys[order[b]].Compare(keys[order[a]]) < 0
                } else {
                    let r = try object.ToNumber(try object.Call(cmp, .undefined, [vals[order[b]], vals[order[a]]]))
                    takeB = r < 0
                }
                if takeB {
                    tmp[t] = order[b]
                    b += 1
                } else {
                    tmp[t] = order[a]
                    a += 1
                }
                t += 1
            }
            while a < mid { tmp[t] = order[a]; a += 1; t += 1 }
            while b < hi { tmp[t] = order[b]; b += 1; t += 1 }
            lo += 2 * width
        }
        let swap = order
        order = tmp
        tmp = swap
        width *= 2
    }
    var out: [Value] = []
    for j in order { out.append(vals[j]) }
    var u = 0
    while u < undefs { out.append(.undefined); u += 1 }
    return out
}

// MARK: copying

func installCopying(_ r: object.Realm, _ ap: object.JSObject) {
    r.Method(ap, "concat", 1) { thisV, args, _ in
        let o = try object.ToObject(thisV)
        let a = try object.ArraySpeciesCreate(o, 0)
        var n = 0
        var items: [Value] = [.object(o)]
        items.append(contentsOf: args)
        for e in items {
            var spreadable = false
            if case .object(let eo) = e {
                let s = try eo.Get(.symbol(value.SymIsConcatSpreadable), e)
                spreadable = s.IsUndefined ? try object.IsArray(e) : s.Truthy
                if spreadable {
                    let len = try object.LengthOfArrayLike(eo)
                    try checkLength(float64(n + len))
                    var k = 0
                    while k < len {
                        if try has(eo, k) {
                            try object.CreateDataPropertyOrThrow(a, idx(n), try get(eo, k))
                        }
                        n += 1
                        k += 1
                    }
                }
            }
            if !spreadable {
                try checkLength(float64(n + 1))
                try object.CreateDataPropertyOrThrow(a, idx(n), e)
                n += 1
            }
        }
        try setLength(a, n)
        return .object(a)
    }
    r.Method(ap, "slice", 2) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let k0 = try relative(object.Arg(args, 0), len, 0)
        let fin = try relative(object.Arg(args, 1), len, len)
        let count = max(fin - k0, 0)
        let a = try object.ArraySpeciesCreate(o, float64(count))
        var k = k0
        var n = 0
        while k < fin {
            if try has(o, k) {
                try object.CreateDataPropertyOrThrow(a, idx(n), try get(o, k))
            }
            k += 1
            n += 1
        }
        try setLength(a, n)
        return .object(a)
    }
    r.Method(ap, "toReversed", 0) { thisV, _, _ in
        let (o, len) = try thisObject(thisV)
        var out: [Value] = []
        var k = len - 1
        while k >= 0 { out.append(try get(o, k)); k -= 1 }
        return .object(object.CreateArrayFromList(r, out))
    }
    r.Method(ap, "toSorted", 1) { thisV, args, _ in
        let cmp = object.Arg(args, 0)
        if !cmp.IsUndefined && !cmp.IsCallable {
            throw object.ThrowTypeError("The comparison function must be either a function or undefined")
        }
        let (o, len) = try thisObject(thisV)
        if len > 4294967295 { throw object.ThrowRangeError("Invalid array length") }
        return .object(object.CreateArrayFromList(r, try sortValues(try collect(o, len, skipHoles: false), cmp)))
    }
    r.Method(ap, "toSpliced", 2) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let start = try relative(object.Arg(args, 0), len, 0)
        var skip = 0
        var items: [Value] = []
        if args.count == 0 {
            skip = 0
        } else if args.count == 1 {
            skip = len - start
        } else {
            let dc = try object.ToIntegerOrInfinity(args[1])
            skip = dc < 0 ? 0 : (dc > float64(len - start) ? len - start : int(dc))
            var i = 2
            while i < args.count { items.append(args[i]); i += 1 }
        }
        let newLen = len + items.count - skip
        try checkLength(float64(newLen))
        if newLen > 4294967295 { throw object.ThrowRangeError("Invalid array length") }
        var out: [Value] = []
        var k = 0
        while k < start { out.append(try get(o, k)); k += 1 }
        out.append(contentsOf: items)
        k = start + skip
        while k < len { out.append(try get(o, k)); k += 1 }
        return .object(object.CreateArrayFromList(r, out))
    }
    r.Method(ap, "with", 2) { thisV, args, _ in
        let (o, len) = try thisObject(thisV)
        let rel = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        let at = rel >= 0 ? rel : float64(len) + rel
        if at >= float64(len) || at < 0 { throw object.ThrowRangeError("Invalid index : \(value.NumberToString(rel))") }
        if len > 4294967295 { throw object.ThrowRangeError("Invalid array length") }
        var out: [Value] = []
        var k = 0
        while k < len {
            out.append(k == int(at) ? object.Arg(args, 1) : try get(o, k))
            k += 1
        }
        return .object(object.CreateArrayFromList(r, out))
    }
}

// MARK: iterators (§23.1.5)

public enum IterationKind {
    case keys
    case values
    case entries
}

/// ArrayIterator is an Array Iterator object: it walks any array-like,
/// typed arrays included.
public final class ArrayIterator: object.JSObject {
    public var Iterated: object.JSObject?
    public var Index: int = 0
    public let Mode: IterationKind

    public init(_ o: object.JSObject, _ kind: IterationKind, proto: object.JSObject) {
        self.Iterated = o
        self.Mode = kind
        super.init(proto: proto)
    }
}

/// CreateArrayIterator (§23.1.5.1).
public func CreateArrayIterator(_ r: object.Realm, _ o: object.JSObject, _ kind: IterationKind) -> ArrayIterator {
    return ArrayIterator(o, kind, proto: r.ArrayIteratorPrototype)
}

func installIterators(_ r: object.Realm, _ ap: object.JSObject) {
    let values = r.Function("values", 0) { thisV, _, _ in
        return .object(CreateArrayIterator(r, try object.ToObject(thisV), .values))
    }
    ap.DefineData(key("values"), .object(values), writable: true, enumerable: false, configurable: true)
    ap.DefineData(.symbol(value.SymIterator), .object(values), writable: true, enumerable: false, configurable: true)
    r.Intrinsics["ArrayValues"] = values
    r.Method(ap, "keys", 0) { thisV, _, _ in
        return .object(CreateArrayIterator(r, try object.ToObject(thisV), .keys))
    }
    r.Method(ap, "entries", 0) { thisV, _, _ in
        return .object(CreateArrayIterator(r, try object.ToObject(thisV), .entries))
    }

    let aip = r.ArrayIteratorPrototype
    let next = r.Function("next", 0) { thisV, _, _ in
        guard case .object(let io) = thisV, let it = io as? ArrayIterator else {
            throw object.ThrowTypeError("Method Array Iterator.prototype.next called on incompatible receiver \(object.Describe(thisV))")
        }
        guard let o = it.Iterated else { return .object(object.CreateIterResultObject(.undefined, true)) }
        var len = 0
        if o.Kind == .typedArray, let tl = TypedArrayLength {
            len = try tl(o)
        } else {
            len = try object.LengthOfArrayLike(o)
        }
        let i = it.Index
        if i >= len {
            it.Iterated = nil
            return .object(object.CreateIterResultObject(.undefined, true))
        }
        it.Index = i + 1
        switch it.Mode {
        case .keys:
            return .object(object.CreateIterResultObject(.number(float64(i)), false))
        case .values:
            return .object(object.CreateIterResultObject(try get(o, i), false))
        case .entries:
            let pair = object.CreateArrayFromList(r, [.number(float64(i)), try get(o, i)])
            return .object(object.CreateIterResultObject(.object(pair), false))
        }
    }
    aip.DefineData(key("next"), .object(next), writable: true, enumerable: false, configurable: true)
    r.Intrinsics["ArrayIteratorNext"] = next
    aip.DefineData(.symbol(value.SymToStringTag), .string(str.Name("Array Iterator")), writable: false, enumerable: false, configurable: true)
}

// MARK: Array.fromAsync (§23.1.2.2)

/// fromAsyncSource is Array.fromAsync, self-hosted: an async function is
/// the spec's algorithm almost line for line. The iterator method is got
/// once, as GetMethod does, and handed to for await through a wrapper;
/// for await closes the iterator when mapping or defining throws.
let fromAsyncSource = """
function (arrayConstruct, defineElement, setLength, isCallable, call, asyncIteratorSym, iteratorSym, toObject, lengthOf) {
    "use strict";
    return async function fromAsync(asyncItems, mapfn = undefined, thisArg = undefined) {
        const C = this;
        const mapping = mapfn !== undefined;
        if (mapping && !isCallable(mapfn)) throw new TypeError(String(mapfn) + " is not a function");
        const usingAsync = asyncItems == null ? undefined : asyncItems[asyncIteratorSym];
        if (asyncItems == null) toObject(asyncItems);
        const usingSync = usingAsync == null ? asyncItems[iteratorSym] : undefined;
        if (usingAsync != null || usingSync != null) {
            const method = usingAsync != null ? usingAsync : usingSync;
            if (!isCallable(method)) throw new TypeError("object is not iterable");
            const A = arrayConstruct(C, -1);
            const source = usingAsync != null
                ? { [asyncIteratorSym]() { return call(method, asyncItems); } }
                : { [iteratorSym]() { return call(method, asyncItems); } };
            let k = 0;
            for await (const next of source) {
                if (k >= 9007199254740991) throw new TypeError("Array.fromAsync: too many elements");
                const v = mapping ? await call(mapfn, thisArg, next, k) : next;
                defineElement(A, k, v);
                k++;
            }
            setLength(A, k);
            return A;
        }
        const arrayLike = toObject(asyncItems);
        const len = lengthOf(arrayLike);
        const A = arrayConstruct(C, len);
        for (let k = 0; k < len; k++) {
            const kValue = await arrayLike[k];
            const v = mapping ? await call(mapfn, thisArg, kValue, k) : kValue;
            defineElement(A, k, v);
        }
        setLength(A, len);
        return A;
    };
}
"""

func installFromAsync(_ r: object.Realm, _ ctor: object.JSObject) {
    let helpers: [Value] = [
        .object(r.Function("arrayConstruct", 2) { _, a, _ in
            let n = try object.ToNumber(object.Arg(a, 1))
            return .object(try construct(object.Arg(a, 0), int(n)))
        }),
        .object(r.Function("defineElement", 3) { _, a, _ in
            guard case .object(let o) = object.Arg(a, 0) else { return .undefined }
            try object.CreateDataPropertyOrThrow(o, idx(int(try object.ToNumber(object.Arg(a, 1)))), object.Arg(a, 2))
            return .undefined
        }),
        .object(r.Function("setLength", 2) { _, a, _ in
            guard case .object(let o) = object.Arg(a, 0) else { return .undefined }
            try setLength(o, int(try object.ToNumber(object.Arg(a, 1))))
            return .undefined
        }),
        .object(r.Function("isCallable", 1) { _, a, _ in
            return .bool(object.Arg(a, 0).IsCallable)
        }),
        .object(r.Function("call", 2) { _, a, _ in
            var rest: [Value] = []
            var i = 2
            while i < a.count { rest.append(a[i]); i += 1 }
            return try object.Call(object.Arg(a, 0), object.Arg(a, 1), rest)
        }),
        .symbol(value.SymAsyncIterator),
        .symbol(value.SymIterator),
        .object(r.Function("toObject", 1) { _, a, _ in
            return .object(try object.ToObject(object.Arg(a, 0)))
        }),
        .object(r.Function("lengthOf", 1) { _, a, _ in
            guard case .object(let o) = object.Arg(a, 0) else { return .number(0) }
            return .number(float64(try object.LengthOfArrayLike(o)))
        }),
    ]
    do {
        let fn = try r.SelfHosted(fromAsyncSource, helpers)
        ctor.DefineData(object.Key("fromAsync"), .object(fn), writable: true, enumerable: false, configurable: true)
    } catch {
    }
}
