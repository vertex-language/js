// Package reflection installs reflection (ECMA-262 §28): Reflect and
// Proxy. The Proxy exotic object itself is js/object's ProxyObject.
package reflection

import (
    "js/object"
    "js/str"
    "js/value"
)

typealias Value = object.Value

func key(_ s: string) -> value.PropertyKey { return value.PropertyKey.Named(s) }

func target(_ v: Value, _ method: string) throws -> object.JSObject {
    guard case .object(let o) = v else {
        throw object.ThrowTypeError("Reflect.\(method) called on non-object")
    }
    return o
}

/// Install defines Reflect and Proxy.
public func Install(_ r: object.Realm) {
    installReflect(r)
    installProxy(r)
}

func installReflect(_ r: object.Realm) {
    let rf = object.JSObject(proto: r.ObjectPrototype)
    r.DefineGlobal("Reflect", .object(rf))
    rf.DefineData(.symbol(value.SymToStringTag), .string(str.Name("Reflect")), writable: false, enumerable: false, configurable: true)
    r.Method(rf, "apply", 3) { _, args, _ in
        let f = object.Arg(args, 0)
        if !f.IsCallable { throw object.ThrowTypeError("Function.prototype.apply was called on \(object.Describe(f)), which is \(f.TypeOf) and not a function") }
        return try object.Call(f, object.Arg(args, 1), try object.CreateListFromArrayLike(object.Arg(args, 2)))
    }
    r.Method(rf, "construct", 2) { _, args, _ in
        guard case .object(let f) = object.Arg(args, 0), f.IsConstructor else {
            throw object.ThrowTypeError("\(object.Describe(object.Arg(args, 0))) is not a constructor")
        }
        var nt = f
        if args.count > 2 {
            guard case .object(let n) = args[2], n.IsConstructor else {
                throw object.ThrowTypeError("\(object.Describe(args[2])) is not a constructor")
            }
            nt = n
        }
        return try object.Construct(f, try object.CreateListFromArrayLike(object.Arg(args, 1)), nt)
    }
    r.Method(rf, "defineProperty", 3) { _, args, _ in
        let o = try target(object.Arg(args, 0), "defineProperty")
        let k = try object.ToPropertyKey(object.Arg(args, 1))
        let d = try object.ToPropertyDescriptor(object.Arg(args, 2))
        return .bool(try o.DefineOwnProperty(k, d))
    }
    r.Method(rf, "deleteProperty", 2) { _, args, _ in
        let o = try target(object.Arg(args, 0), "deleteProperty")
        return .bool(try o.Delete(try object.ToPropertyKey(object.Arg(args, 1))))
    }
    r.Method(rf, "get", 2) { _, args, _ in
        let o = try target(object.Arg(args, 0), "get")
        let k = try object.ToPropertyKey(object.Arg(args, 1))
        let receiver = args.count > 2 ? args[2] : args[0]
        return try o.Get(k, receiver)
    }
    r.Method(rf, "getOwnPropertyDescriptor", 2) { _, args, _ in
        let o = try target(object.Arg(args, 0), "getOwnPropertyDescriptor")
        return object.FromPropertyDescriptor(try o.GetOwnProperty(try object.ToPropertyKey(object.Arg(args, 1))))
    }
    r.Method(rf, "getPrototypeOf", 1) { _, args, _ in
        let o = try target(object.Arg(args, 0), "getPrototypeOf")
        if let p = try o.GetPrototypeOf() { return .object(p) }
        return .null
    }
    r.Method(rf, "has", 2) { _, args, _ in
        let o = try target(object.Arg(args, 0), "has")
        return .bool(try o.HasProperty(try object.ToPropertyKey(object.Arg(args, 1))))
    }
    r.Method(rf, "isExtensible", 1) { _, args, _ in
        return .bool(try target(object.Arg(args, 0), "isExtensible").IsExtensibleObject())
    }
    r.Method(rf, "ownKeys", 1) { _, args, _ in
        let o = try target(object.Arg(args, 0), "ownKeys")
        var out: [Value] = []
        for k in try o.OwnPropertyKeys() { out.append(object.KeyToValue(k)) }
        return .object(object.CreateArrayFromList(r, out))
    }
    r.Method(rf, "preventExtensions", 1) { _, args, _ in
        return .bool(try target(object.Arg(args, 0), "preventExtensions").PreventExtensions())
    }
    r.Method(rf, "set", 3) { _, args, _ in
        let o = try target(object.Arg(args, 0), "set")
        let k = try object.ToPropertyKey(object.Arg(args, 1))
        let receiver = args.count > 3 ? args[3] : args[0]
        return .bool(try o.Set(k, object.Arg(args, 2), receiver))
    }
    r.Method(rf, "setPrototypeOf", 2) { _, args, _ in
        let o = try target(object.Arg(args, 0), "setPrototypeOf")
        let p = object.Arg(args, 1)
        var proto: object.JSObject? = nil
        if case .object(let po) = p { proto = po } else if !p.IsNull {
            throw object.ThrowTypeError("Object prototype may only be an Object or null: \(object.Describe(p))")
        }
        return .bool(try o.SetPrototypeOf(proto))
    }
}

func installProxy(_ r: object.Realm) {
    func create(_ t: Value, _ h: Value) throws -> object.ProxyObject {
        guard case .object(let to) = t, case .object(let ho) = h else {
            throw object.ThrowTypeError("Cannot create proxy with a non-object as target or handler")
        }
        return object.ProxyObject(target: to, handler: ho)
    }
    let construct = object.NativeFunction(realm: r, name: "Proxy", length: 2, constructor: true) { _, args, nt in
        if nt == nil { throw object.ThrowTypeError("Constructor Proxy requires 'new'") }
        return .object(try create(object.Arg(args, 0), object.Arg(args, 1)))
    }
    r.DefineGlobal("Proxy", .object(construct))
    r.Method(construct, "revocable", 2) { _, args, _ in
        let p = try create(object.Arg(args, 0), object.Arg(args, 1))
        var proxy: object.ProxyObject? = p
        let revoke = r.Function("", 0) { _, _, _ in
            if let px = proxy {
                px.Target = nil
                px.Handler = nil
                proxy = nil
            }
            return .undefined
        }
        let o = object.JSObject(proto: r.ObjectPrototype)
        try object.CreateDataPropertyOrThrow(o, key("proxy"), .object(p))
        try object.CreateDataPropertyOrThrow(o, key("revoke"), .object(revoke))
        return .object(o)
    }
}
