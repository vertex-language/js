// Package fundamental installs the fundamental objects (ECMA-262 §20):
// Object, Function, Boolean, Symbol, and Error with its native errors.
package fundamental

import (
    "js/object"
    "js/str"
    "js/value"
)

typealias Value = object.Value

func key(_ s: string) -> value.PropertyKey { return value.PropertyKey.Named(s) }

/// Install defines the fundamental objects in a realm.
public func Install(_ r: object.Realm) {
    installObject(r)
    installFunction(r)
    installBoolean(r)
    installSymbol(r)
    installErrors(r)
    r.DefineGlobal("globalThis", .object(r.Global))
}

// MARK: Object (§20.1)

func installObject(_ r: object.Realm) {
    let op = r.ObjectPrototype
    let ctor = r.Constructor("Object", 1, prototype: op) { _, args, nt in
        if let n = nt, n !== r.ObjectConstructor! {
            return .object(try object.OrdinaryCreateFromConstructor(n, r.ObjectPrototype))
        }
        let v = object.Arg(args, 0)
        if v.IsNullish { return .object(object.JSObject(proto: r.ObjectPrototype)) }
        return .object(try object.ToObject(v))
    }
    r.ObjectConstructor = ctor

    r.Method(ctor, "assign", 2) { _, args, _ in
        let to = try object.ToObject(object.Arg(args, 0))
        var i = 1
        while i < args.count {
            let src = args[i]
            i += 1
            if src.IsNullish { continue }
            let from = try object.ToObject(src)
            for k in try from.OwnPropertyKeys() {
                if let d = try from.GetOwnProperty(k), d.Enumerable == true {
                    let v = try from.Get(k, .object(from))
                    try object.SetProperty(to, k, v, throwing: true)
                }
            }
        }
        return .object(to)
    }
    r.Method(ctor, "create", 2) { _, args, _ in
        let p = object.Arg(args, 0)
        var proto: object.JSObject? = nil
        if case .object(let po) = p {
            proto = po
        } else if !p.IsNull {
            throw object.ThrowTypeError("Object prototype may only be an Object or null: \(object.Describe(p))")
        }
        let o = object.JSObject(proto: proto)
        let props = object.Arg(args, 1)
        if !props.IsUndefined { try defineProperties(o, props) }
        return .object(o)
    }
    r.Method(ctor, "defineProperty", 3) { _, args, _ in
        guard case .object(let o) = object.Arg(args, 0) else {
            throw object.ThrowTypeError("Object.defineProperty called on non-object")
        }
        let k = try object.ToPropertyKey(object.Arg(args, 1))
        let d = try object.ToPropertyDescriptor(object.Arg(args, 2))
        try object.DefinePropertyOrThrow(o, k, d)
        return args[0]
    }
    r.Method(ctor, "defineProperties", 2) { _, args, _ in
        guard case .object(let o) = object.Arg(args, 0) else {
            throw object.ThrowTypeError("Object.defineProperties called on non-object")
        }
        try defineProperties(o, object.Arg(args, 1))
        return args[0]
    }
    r.Method(ctor, "entries", 1) { _, args, _ in
        let o = try object.ToObject(object.Arg(args, 0))
        return .object(object.CreateArrayFromList(r, try object.EnumerableOwnProperties(o, .entries)))
    }
    r.Method(ctor, "keys", 1) { _, args, _ in
        let o = try object.ToObject(object.Arg(args, 0))
        return .object(object.CreateArrayFromList(r, try object.EnumerableOwnProperties(o, .keys)))
    }
    r.Method(ctor, "values", 1) { _, args, _ in
        let o = try object.ToObject(object.Arg(args, 0))
        return .object(object.CreateArrayFromList(r, try object.EnumerableOwnProperties(o, .values)))
    }
    r.Method(ctor, "freeze", 1) { _, args, _ in
        guard case .object(let o) = object.Arg(args, 0) else { return object.Arg(args, 0) }
        if !(try object.SetIntegrityLevel(o, frozen: true)) {
            throw object.ThrowTypeError("Cannot freeze")
        }
        return args[0]
    }
    r.Method(ctor, "seal", 1) { _, args, _ in
        guard case .object(let o) = object.Arg(args, 0) else { return object.Arg(args, 0) }
        if !(try object.SetIntegrityLevel(o, frozen: false)) {
            throw object.ThrowTypeError("Cannot seal")
        }
        return args[0]
    }
    r.Method(ctor, "preventExtensions", 1) { _, args, _ in
        guard case .object(let o) = object.Arg(args, 0) else { return object.Arg(args, 0) }
        if !(try o.PreventExtensions()) {
            throw object.ThrowTypeError("Cannot prevent extensions")
        }
        return args[0]
    }
    r.Method(ctor, "isFrozen", 1) { _, args, _ in
        guard case .object(let o) = object.Arg(args, 0) else { return .bool(true) }
        return .bool(try object.TestIntegrityLevel(o, frozen: true))
    }
    r.Method(ctor, "isSealed", 1) { _, args, _ in
        guard case .object(let o) = object.Arg(args, 0) else { return .bool(true) }
        return .bool(try object.TestIntegrityLevel(o, frozen: false))
    }
    r.Method(ctor, "isExtensible", 1) { _, args, _ in
        guard case .object(let o) = object.Arg(args, 0) else { return .bool(false) }
        return .bool(try o.IsExtensibleObject())
    }
    r.Method(ctor, "fromEntries", 1) { _, args, _ in
        let iterable = object.Arg(args, 0)
        try object.RequireObjectCoercible(iterable)
        let o = object.JSObject(proto: r.ObjectPrototype)
        let rec = try object.GetIterator(iterable)
        while let entry = try object.IteratorStepValue(rec) {
            guard case .object(let eo) = entry else {
                object.IteratorCloseOnThrow(rec)
                throw object.ThrowTypeError("Iterator value \(object.Describe(entry)) is not an entry object")
            }
            do {
                let k = try eo.Get(.index(0), entry)
                let v = try eo.Get(.index(1), entry)
                try object.CreateDataPropertyOrThrow(o, try object.ToPropertyKey(k), v)
            } catch {
                object.IteratorCloseOnThrow(rec)
                throw error
            }
        }
        return .object(o)
    }
    r.Method(ctor, "getOwnPropertyDescriptor", 2) { _, args, _ in
        let o = try object.ToObject(object.Arg(args, 0))
        let k = try object.ToPropertyKey(object.Arg(args, 1))
        return object.FromPropertyDescriptor(try o.GetOwnProperty(k))
    }
    r.Method(ctor, "getOwnPropertyDescriptors", 1) { _, args, _ in
        let o = try object.ToObject(object.Arg(args, 0))
        let out = object.JSObject(proto: r.ObjectPrototype)
        for k in try o.OwnPropertyKeys() {
            let d = object.FromPropertyDescriptor(try o.GetOwnProperty(k))
            if !d.IsUndefined { try object.CreateDataPropertyOrThrow(out, k, d) }
        }
        return .object(out)
    }
    r.Method(ctor, "getOwnPropertyNames", 1) { _, args, _ in
        let o = try object.ToObject(object.Arg(args, 0))
        var out: [Value] = []
        for k in try o.OwnPropertyKeys() where !k.IsSymbol { out.append(object.KeyToValue(k)) }
        return .object(object.CreateArrayFromList(r, out))
    }
    r.Method(ctor, "getOwnPropertySymbols", 1) { _, args, _ in
        let o = try object.ToObject(object.Arg(args, 0))
        var out: [Value] = []
        for k in try o.OwnPropertyKeys() where k.IsSymbol { out.append(object.KeyToValue(k)) }
        return .object(object.CreateArrayFromList(r, out))
    }
    r.Method(ctor, "getPrototypeOf", 1) { _, args, _ in
        let o = try object.ToObject(object.Arg(args, 0))
        if let p = try o.GetPrototypeOf() { return .object(p) }
        return .null
    }
    r.Method(ctor, "setPrototypeOf", 2) { _, args, _ in
        let v = object.Arg(args, 0)
        try object.RequireObjectCoercible(v)
        let p = object.Arg(args, 1)
        var proto: object.JSObject? = nil
        if case .object(let po) = p { proto = po } else if !p.IsNull {
            throw object.ThrowTypeError("Object prototype may only be an Object or null: \(object.Describe(p))")
        }
        guard case .object(let o) = v else { return v }
        if !(try o.SetPrototypeOf(proto)) {
            throw object.ThrowTypeError(o.Extensible ? "Cyclic __proto__ value" : "\(object.Describe(v)) is not extensible")
        }
        return v
    }
    r.Method(ctor, "hasOwn", 2) { _, args, _ in
        let o = try object.ToObject(object.Arg(args, 0))
        return .bool(try object.HasOwnProperty(o, try object.ToPropertyKey(object.Arg(args, 1))))
    }
    r.Method(ctor, "is", 2) { _, args, _ in
        return .bool(object.SameValue(object.Arg(args, 0), object.Arg(args, 1)))
    }
    r.Method(ctor, "groupBy", 2) { _, args, _ in
        let groups = try groupBy(object.Arg(args, 0), object.Arg(args, 1), propertyKeys: true)
        let o = object.JSObject(proto: nil)
        for (k, list) in groups {
            try object.CreateDataPropertyOrThrow(o, try object.ToPropertyKey(k), .object(object.CreateArrayFromList(r, list)))
        }
        return .object(o)
    }

    // Object.prototype
    r.Method(op, "hasOwnProperty", 1) { thisV, args, _ in
        let k = try object.ToPropertyKey(object.Arg(args, 0))
        let o = try object.ToObject(thisV)
        return .bool(try object.HasOwnProperty(o, k))
    }
    r.Method(op, "isPrototypeOf", 1) { thisV, args, _ in
        guard case .object(var v) = object.Arg(args, 0) else { return .bool(false) }
        let o = try object.ToObject(thisV)
        while true {
            guard let p = try v.GetPrototypeOf() else { return .bool(false) }
            if p === o { return .bool(true) }
            v = p
        }
    }
    r.Method(op, "propertyIsEnumerable", 1) { thisV, args, _ in
        let k = try object.ToPropertyKey(object.Arg(args, 0))
        let o = try object.ToObject(thisV)
        guard let d = try o.GetOwnProperty(k) else { return .bool(false) }
        return .bool(d.Enumerable == true)
    }
    r.Method(op, "toString", 0) { thisV, _, _ in
        return .string(try ObjectToString(thisV))
    }
    r.Method(op, "toLocaleString", 0) { thisV, _, _ in
        return try object.Invoke(thisV, key("toString"), [])
    }
    r.Method(op, "valueOf", 0) { thisV, _, _ in
        return .object(try object.ToObject(thisV))
    }
    r.Accessor(op, "__proto__", get: { thisV, _, _ in
        let o = try object.ToObject(thisV)
        if let p = try o.GetPrototypeOf() { return .object(p) }
        return .null
    }, set: { thisV, args, _ in
        try object.RequireObjectCoercible(thisV)
        let p = object.Arg(args, 0)
        guard case .object(let o) = thisV else { return .undefined }
        var proto: object.JSObject? = nil
        if case .object(let po) = p { proto = po } else if !p.IsNull { return .undefined }
        if !(try o.SetPrototypeOf(proto)) {
            throw object.ThrowTypeError("Cyclic __proto__ value")
        }
        return .undefined
    })
    r.Method(op, "__defineGetter__", 2) { thisV, args, _ in
        let o = try object.ToObject(thisV)
        guard object.Arg(args, 1).IsCallable else { throw object.ThrowTypeError("Object.prototype.__defineGetter__: Expecting function") }
        var d = object.PropertyDescriptor()
        d.Get = args[1]
        d.Enumerable = true
        d.Configurable = true
        try object.DefinePropertyOrThrow(o, try object.ToPropertyKey(object.Arg(args, 0)), d)
        return .undefined
    }
    r.Method(op, "__defineSetter__", 2) { thisV, args, _ in
        let o = try object.ToObject(thisV)
        guard object.Arg(args, 1).IsCallable else { throw object.ThrowTypeError("Object.prototype.__defineSetter__: Expecting function") }
        var d = object.PropertyDescriptor()
        d.Set = args[1]
        d.Enumerable = true
        d.Configurable = true
        try object.DefinePropertyOrThrow(o, try object.ToPropertyKey(object.Arg(args, 0)), d)
        return .undefined
    }
    r.Method(op, "__lookupGetter__", 1) { thisV, args, _ in
        var o: object.JSObject? = try object.ToObject(thisV)
        let k = try object.ToPropertyKey(object.Arg(args, 0))
        while let cur = o {
            if let d = try cur.GetOwnProperty(k) { return d.Get ?? .undefined }
            o = try cur.GetPrototypeOf()
        }
        return .undefined
    }
    r.Method(op, "__lookupSetter__", 1) { thisV, args, _ in
        var o: object.JSObject? = try object.ToObject(thisV)
        let k = try object.ToPropertyKey(object.Arg(args, 0))
        while let cur = o {
            if let d = try cur.GetOwnProperty(k) { return d.Set ?? .undefined }
            o = try cur.GetPrototypeOf()
        }
        return .undefined
    }
}

func defineProperties(_ o: object.JSObject, _ props: Value) throws {
    let p = try object.ToObject(props)
    var descs: [(value.PropertyKey, object.PropertyDescriptor)] = []
    for k in try p.OwnPropertyKeys() {
        if let d = try p.GetOwnProperty(k), d.Enumerable == true {
            descs.append((k, try object.ToPropertyDescriptor(try p.Get(k, .object(p)))))
        }
    }
    for (k, d) in descs {
        try object.DefinePropertyOrThrow(o, k, d)
    }
}

/// groupBy is GroupBy (§7.3.35): the groups in first-seen order.
public func groupBy(_ items: Value, _ cb: Value, propertyKeys: bool) throws -> [(Value, [Value])] {
    try object.RequireObjectCoercible(items)
    guard cb.IsCallable else { throw object.ThrowTypeError("\(object.Describe(cb)) is not a function") }
    var groups: [(Value, [Value])] = []
    let rec = try object.GetIterator(items)
    var k = 0
    while let v = try object.IteratorStepValue(rec) {
        var key: Value
        do {
            key = try object.Call(cb, .undefined, [v, .number(float64(k))])
            if propertyKeys {
                key = object.KeyToValue(try object.ToPropertyKey(key))
            } else if case .number(let d) = key, d == 0 {
                key = .number(0)
            }
        } catch {
            object.IteratorCloseOnThrow(rec)
            throw error
        }
        var found = false
        var i = 0
        while i < groups.count {
            if object.SameValueZero(groups[i].0, key) {
                groups[i].1.append(v)
                found = true
                break
            }
            i += 1
        }
        if !found { groups.append((key, [v])) }
        k += 1
    }
    return groups
}

/// ObjectToString is Object.prototype.toString (§20.1.3.6).
public func ObjectToString(_ v: Value) throws -> str.JSString {
    if v.IsUndefined { return str.Name("[object Undefined]") }
    if v.IsNull { return str.Name("[object Null]") }
    let o = try object.ToObject(v)
    var tag = "Object"
    if try object.IsArray(.object(o)) {
        tag = "Array"
    } else {
        switch o.Kind {
        case .arguments: tag = "Arguments"
        case .function: tag = "Function"
        case .error: tag = "Error"
        case .boolean: tag = "Boolean"
        case .number: tag = "Number"
        case .string: tag = "String"
        case .date: tag = "Date"
        case .regexp: tag = "RegExp"
        default:
            if o.IsCallable { tag = "Function" }
        }
    }
    let t = try o.Get(.symbol(value.SymToStringTag), .object(o))
    if case .string(let s) = t { tag = s.String }
    return str.JSString.From("[object " + tag + "]")
}

// MARK: Function (§20.2)

func installFunction(_ r: object.Realm) {
    let fp = r.FunctionPrototype
    fp.DefineData(key("length"), .number(0), writable: false, enumerable: false, configurable: true)
    fp.DefineData(key("name"), .string(str.JSString.Empty), writable: false, enumerable: false, configurable: true)
    let ctor = r.Constructor("Function", 1, prototype: fp) { _, args, nt in
        return .object(try r.Engine!.CreateDynamicFunction(r, args, nt, isAsync: false, isGenerator: false))
    }
    r.FunctionConstructor = ctor
    r.Method(fp, "call", 1) { thisV, args, _ in
        guard thisV.IsCallable else { throw object.ThrowTypeError("Function.prototype.call called on non-function") }
        var rest: [Value] = []
        var i = 1
        while i < args.count { rest.append(args[i]); i += 1 }
        return try object.Call(thisV, object.Arg(args, 0), rest)
    }
    r.Method(fp, "apply", 2) { thisV, args, _ in
        guard thisV.IsCallable else { throw object.ThrowTypeError("Function.prototype.apply was called on \(object.Describe(thisV)), which is \(thisV.TypeOf) and not a function") }
        let list = object.Arg(args, 1)
        if list.IsNullish { return try object.Call(thisV, object.Arg(args, 0), []) }
        return try object.Call(thisV, object.Arg(args, 0), try object.CreateListFromArrayLike(list))
    }
    r.Method(fp, "bind", 1) { thisV, args, _ in
        guard case .object(let target) = thisV, target.IsCallable else {
            throw object.ThrowTypeError("Bind must be called on a function")
        }
        var bound: [Value] = []
        var i = 1
        while i < args.count { bound.append(args[i]); i += 1 }
        let f = object.BoundFunction(target: target, boundThis: object.Arg(args, 0), boundArgs: bound, proto: try target.GetPrototypeOf())
        var length: float64 = 0
        if try object.HasOwnProperty(target, key("length")) {
            let l = try target.Get(key("length"), thisV)
            if case .number(let d) = l {
                if d.isInfinite { length = d > 0 ? d : 0 } else {
                    let li = value.ToIntegerOrInfinity(d)
                    length = li - float64(bound.count)
                    if length < 0 { length = 0 }
                }
            }
        }
        f.DefineData(key("length"), .number(length), writable: false, enumerable: false, configurable: true)
        var name = try target.Get(key("name"), thisV)
        if !name.IsString { name = .string(str.JSString.Empty) }
        if case .string(let ns) = name {
            f.DefineData(key("name"), .string(str.Name("bound ").Concat(ns)), writable: false, enumerable: false, configurable: true)
        }
        return .object(f)
    }
    r.Method(fp, "toString", 0) { thisV, _, _ in
        return .string(str.JSString.From(try FunctionToString(thisV)))
    }
    r.SymbolMethod(fp, value.SymHasInstance, 1, writable: false, configurable: false) { thisV, args, _ in
        return .bool(try object.OrdinaryHasInstance(thisV, object.Arg(args, 0)))
    }
    // %ThrowTypeError% (§10.2.4.1).
    let thrower = r.Function("", 0) { _, _, _ in
        throw object.ThrowTypeError("'caller', 'callee', and 'arguments' properties may not be accessed on strict mode functions or the arguments objects for calls to them")
    }
    _ = try? thrower.PreventExtensions()
    r.ThrowTypeError = thrower
    r.Intrinsics["ThrowTypeError"] = thrower
    fp.DefineAccessorDirect(key("caller"), getter: thrower, setter: thrower, enumerable: false, configurable: true)
    fp.DefineAccessorDirect(key("arguments"), getter: thrower, setter: thrower, enumerable: false, configurable: true)
}

/// FunctionToString is Function.prototype.toString (§20.2.3.5).
public func FunctionToString(_ v: Value) throws -> string {
    guard case .object(let o) = v, o.IsCallable else {
        throw object.ThrowTypeError("Function.prototype.toString requires that 'this' be a Function")
    }
    if let f = o as? object.JSFunction {
        let s = f.Template.SourceString
        if !s.isEmpty { return s }
    }
    var name = ""
    if let slot = o.OwnSlot(key("name")), case .string(let s) = slot.Value { name = s.String }
    if o is object.BoundFunction { return "function () { [native code] }" }
    return "function \(name)() { [native code] }"
}

// MARK: Boolean (§20.3)

func installBoolean(_ r: object.Realm) {
    let bp = r.BooleanPrototype
    bp.Kind = .boolean
    bp.PrimitiveValue = .bool(false)
    _ = r.Constructor("Boolean", 1, prototype: bp) { _, args, nt in
        let b = object.Arg(args, 0).Truthy
        guard let n = nt else { return .bool(b) }
        let o = try object.OrdinaryCreateFromConstructor(n, r.BooleanPrototype)
        o.Kind = .boolean
        o.PrimitiveValue = .bool(b)
        return .object(o)
    }
    r.Method(bp, "toString", 0) { thisV, _, _ in
        return .string(str.Name(try thisBoolean(thisV, "toString") ? "true" : "false"))
    }
    r.Method(bp, "valueOf", 0) { thisV, _, _ in
        return .bool(try thisBoolean(thisV, "valueOf"))
    }
}

func thisBoolean(_ v: Value, _ method: string) throws -> bool {
    if case .bool(let b) = v { return b }
    if case .object(let o) = v, o.Kind == .boolean, case .bool(let b) = o.PrimitiveValue { return b }
    throw object.ThrowTypeError("Boolean.prototype.\(method) requires that 'this' be a Boolean")
}

// MARK: Symbol (§20.4)

func installSymbol(_ r: object.Realm) {
    let sp = r.SymbolPrototype
    let ctor = r.Constructor("Symbol", 0, prototype: sp) { _, args, nt in
        if nt != nil { throw object.ThrowTypeError("Symbol is not a constructor") }
        let d = object.Arg(args, 0)
        if d.IsUndefined { return .symbol(value.Symbol(nil)) }
        return .symbol(value.Symbol(try object.ToString(d)))
    }
    let wellKnown: [(string, value.Symbol)] = [
        ("asyncIterator", value.SymAsyncIterator), ("hasInstance", value.SymHasInstance),
        ("isConcatSpreadable", value.SymIsConcatSpreadable), ("iterator", value.SymIterator),
        ("match", value.SymMatch), ("matchAll", value.SymMatchAll), ("replace", value.SymReplace),
        ("search", value.SymSearch), ("species", value.SymSpecies), ("split", value.SymSplit),
        ("toPrimitive", value.SymToPrimitive), ("toStringTag", value.SymToStringTag),
        ("unscopables", value.SymUnscopables), ("dispose", value.SymDispose), ("asyncDispose", value.SymAsyncDispose),
    ]
    for (n, s) in wellKnown {
        ctor.DefineData(key(n), .symbol(s), writable: false, enumerable: false, configurable: false)
    }
    r.Method(ctor, "for", 1) { _, args, _ in
        let k = try object.ToString(object.Arg(args, 0))
        if let s = r.Agent.SymbolRegistry[k] { return .symbol(s) }
        let s = value.Symbol(k)
        s.RegistryKey = k
        r.Agent.SymbolRegistry[k] = s
        return .symbol(s)
    }
    r.Method(ctor, "keyFor", 1) { _, args, _ in
        guard case .symbol(let s) = object.Arg(args, 0) else {
            throw object.ThrowTypeError("\(object.Describe(object.Arg(args, 0))) is not a symbol")
        }
        if let k = s.RegistryKey { return .string(k) }
        return .undefined
    }
    r.Method(sp, "toString", 0) { thisV, _, _ in
        let s = try thisSymbol(thisV, "toString")
        return .string(str.JSString.From(s.DescriptiveString))
    }
    r.Method(sp, "valueOf", 0) { thisV, _, _ in
        return .symbol(try thisSymbol(thisV, "valueOf"))
    }
    r.Getter(sp, key("description")) { thisV, _, _ in
        let s = try thisSymbol(thisV, "description")
        if let d = s.Description { return .string(d) }
        return .undefined
    }
    r.SymbolMethod(sp, value.SymToPrimitive, 1, writable: false, configurable: true) { thisV, _, _ in
        return .symbol(try thisSymbol(thisV, "[Symbol.toPrimitive]"))
    }
    sp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("Symbol")), writable: false, enumerable: false, configurable: true)
}

func thisSymbol(_ v: Value, _ method: string) throws -> value.Symbol {
    if case .symbol(let s) = v { return s }
    if case .object(let o) = v, o.Kind == .symbol, case .symbol(let s) = o.PrimitiveValue { return s }
    throw object.ThrowTypeError("Symbol.prototype.\(method) requires that 'this' be a Symbol")
}

// MARK: Error (§20.5)

func installErrors(_ r: object.Realm) {
    let ep = r.ErrorPrototype
    let errorCtor = makeErrorConstructor(r, "Error", ep, parent: nil)
    ep.DefineData(key("name"), .string(str.Name("Error")), writable: true, enumerable: false, configurable: true)
    ep.DefineData(key("message"), .string(str.JSString.Empty), writable: true, enumerable: false, configurable: true)
    r.Method(ep, "toString", 0) { thisV, _, _ in
        guard case .object(let o) = thisV else {
            throw object.ThrowTypeError("Error.prototype.toString requires that 'this' be an Object")
        }
        let n = try o.Get(key("name"), thisV)
        let name = n.IsUndefined ? str.Name("Error") : try object.ToString(n)
        let m = try o.Get(key("message"), thisV)
        let msg = m.IsUndefined ? str.JSString.Empty : try object.ToString(m)
        if name.Length == 0 { return .string(msg) }
        if msg.Length == 0 { return .string(name) }
        return .string(name.Concat(str.Name(": ")).Concat(msg))
    }
    // Error.isError (ES2026): an object with [[ErrorData]], not a proxy of one.
    r.Method(errorCtor, "isError", 1) { _, args, _ in
        if case .object(let o) = object.Arg(args, 0), o.Kind == .error { return .bool(true) }
        return .bool(false)
    }
    // V8's Error.captureStackTrace and stackTraceLimit, which libraries use.
    r.Method(errorCtor, "captureStackTrace", 1) { _, args, _ in
        guard case .object(let o) = object.Arg(args, 0) else {
            throw object.ThrowTypeError("Invalid argument")
        }
        object.InstallStack(o)
        return .undefined
    }
    errorCtor.DefineData(key("stackTraceLimit"), .number(10))
    let natives: [(string, object.JSObject)] = [
        ("EvalError", r.EvalErrorPrototype), ("RangeError", r.RangeErrorPrototype),
        ("ReferenceError", r.ReferenceErrorPrototype), ("SyntaxError", r.SyntaxErrorPrototype),
        ("TypeError", r.TypeErrorPrototype), ("URIError", r.URIErrorPrototype),
    ]
    for (n, p) in natives {
        _ = makeErrorConstructor(r, n, p, parent: errorCtor)
        p.DefineData(key("name"), .string(str.Name(n)), writable: true, enumerable: false, configurable: true)
        p.DefineData(key("message"), .string(str.JSString.Empty), writable: true, enumerable: false, configurable: true)
    }
    // AggregateError(errors, message, options) (§20.5.7).
    let ap = r.AggregateErrorPrototype
    let agg = r.Constructor("AggregateError", 2, prototype: ap) { _, args, nt in
        let o = try object.OrdinaryCreateFromConstructor(nt ?? r.Intrinsics["AggregateError"]!, r.AggregateErrorPrototype)
        o.Kind = .error
        let msg = object.Arg(args, 1)
        if !msg.IsUndefined {
            o.DefineData(key("message"), .string(try object.ToString(msg)), writable: true, enumerable: false, configurable: true)
        }
        try installCause(o, object.Arg(args, 2))
        let errors = try object.IterableToList(object.Arg(args, 0))
        o.DefineData(key("errors"), .object(object.CreateArrayFromList(r, errors)), writable: true, enumerable: false, configurable: true)
        object.InstallStack(o)
        return .object(o)
    }
    agg.Proto = errorCtor
    r.Intrinsics["AggregateError"] = agg

    // SuppressedError(error, suppressed, message) (ES2026).
    let sp = object.JSObject(proto: ep)
    r.Intrinsics["SuppressedErrorPrototype"] = sp
    var suppressedRef: object.JSObject? = nil
    let suppressed = r.Constructor("SuppressedError", 3, prototype: sp) { _, args, nt in
        let o = try object.OrdinaryCreateFromConstructor(nt ?? suppressedRef!, sp)
        o.Kind = .error
        let msg = object.Arg(args, 2)
        if !msg.IsUndefined {
            o.DefineData(key("message"), .string(try object.ToString(msg)), writable: true, enumerable: false, configurable: true)
        }
        o.DefineData(key("error"), object.Arg(args, 0), writable: true, enumerable: false, configurable: true)
        o.DefineData(key("suppressed"), object.Arg(args, 1), writable: true, enumerable: false, configurable: true)
        object.InstallStack(o)
        return .object(o)
    }
    suppressedRef = suppressed
    suppressed.Proto = errorCtor
    r.Intrinsics["SuppressedError"] = suppressed
    sp.DefineData(key("name"), .string(str.Name("SuppressedError")), writable: true, enumerable: false, configurable: true)
    sp.DefineData(key("message"), .string(str.JSString.Empty), writable: true, enumerable: false, configurable: true)
    ap.DefineData(key("name"), .string(str.Name("AggregateError")), writable: true, enumerable: false, configurable: true)
    ap.DefineData(key("message"), .string(str.JSString.Empty), writable: true, enumerable: false, configurable: true)
}

func makeErrorConstructor(_ r: object.Realm, _ name: string, _ proto: object.JSObject, parent: object.JSObject?) -> object.JSObject {
    var selfRef: object.JSObject? = nil
    let ctor = r.Constructor(name, 1, prototype: proto) { _, args, nt in
        let o = try object.OrdinaryCreateFromConstructor(nt ?? selfRef!, proto)
        o.Kind = .error
        let msg = object.Arg(args, 0)
        if !msg.IsUndefined {
            o.DefineData(key("message"), .string(try object.ToString(msg)), writable: true, enumerable: false, configurable: true)
        }
        try installCause(o, object.Arg(args, 1))
        object.InstallStack(o)
        return .object(o)
    }
    selfRef = ctor
    if let p = parent { ctor.Proto = p }
    r.Intrinsics[name] = ctor
    return ctor
}

func installCause(_ o: object.JSObject, _ options: Value) throws {
    if case .object(let opts) = options, try opts.HasProperty(key("cause")) {
        let c = try opts.Get(key("cause"), options)
        o.DefineData(key("cause"), c, writable: true, enumerable: false, configurable: true)
    }
}
