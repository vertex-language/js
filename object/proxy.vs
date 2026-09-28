package object

import (
    "js/value"
)

/// ProxyObject is a Proxy exotic object (§10.5). Target and Handler are
/// nil once revoked.
public final class ProxyObject: JSObject {
    public var Target: JSObject?
    public var Handler: JSObject?
    let callable: bool
    let constructible: bool

    public init(target: JSObject, handler: JSObject) {
        self.Target = target
        self.Handler = handler
        self.callable = target.IsCallable
        self.constructible = target.IsConstructor
        super.init(proto: nil)
        self.Kind = .proxy
    }

    public override var isOrdinaryLookup: bool { return false }
    public override var IsCallable: bool { return callable }
    public override var IsConstructor: bool { return constructible }

    func parts(_ op: string) throws -> (JSObject, JSObject) {
        guard let t = Target, let h = Handler else {
            throw ThrowTypeError("Cannot perform '\(op)' on a proxy that has been revoked")
        }
        return (t, h)
    }

    func trap(_ h: JSObject, _ name: string) throws -> JSObject? {
        let f = try GetMethod(.object(h), Key(name))
        if case .object(let o) = f { return o }
        return nil
    }

    public override func GetPrototypeOf() throws -> JSObject? {
        let (t, h) = try parts("getPrototypeOf")
        guard let tr = try trap(h, "getPrototypeOf") else { return try t.GetPrototypeOf() }
        let r = try tr.Call(.object(h), [.object(t)])
        var proto: JSObject? = nil
        switch r {
        case .object(let o): proto = o
        case .null: proto = nil
        default: throw ThrowTypeError("'getPrototypeOf' on proxy: trap returned neither object nor null")
        }
        if try t.IsExtensibleObject() { return proto }
        if try t.GetPrototypeOf() !== proto {
            throw ThrowTypeError("'getPrototypeOf' on proxy: proxy target is non-extensible but the trap did not return its actual prototype")
        }
        return proto
    }

    public override func SetPrototypeOf(_ v: JSObject?) throws -> bool {
        let (t, h) = try parts("setPrototypeOf")
        guard let tr = try trap(h, "setPrototypeOf") else { return try t.SetPrototypeOf(v) }
        let arg: Value = v == nil ? .null : .object(v!)
        if !(try tr.Call(.object(h), [.object(t), arg]).Truthy) { return false }
        if try t.IsExtensibleObject() { return true }
        if try t.GetPrototypeOf() !== v {
            throw ThrowTypeError("'setPrototypeOf' on proxy: trap returned truish for setting a new prototype on the non-extensible proxy target")
        }
        return true
    }

    public override func IsExtensibleObject() throws -> bool {
        let (t, h) = try parts("isExtensible")
        guard let tr = try trap(h, "isExtensible") else { return try t.IsExtensibleObject() }
        let r = try tr.Call(.object(h), [.object(t)]).Truthy
        if r != (try t.IsExtensibleObject()) {
            throw ThrowTypeError("'isExtensible' on proxy: trap result does not reflect extensibility of proxy target (which is '\(!r)')")
        }
        return r
    }

    public override func PreventExtensions() throws -> bool {
        let (t, h) = try parts("preventExtensions")
        guard let tr = try trap(h, "preventExtensions") else { return try t.PreventExtensions() }
        let r = try tr.Call(.object(h), [.object(t)]).Truthy
        if r && (try t.IsExtensibleObject()) {
            throw ThrowTypeError("'preventExtensions' on proxy: trap returned truish but the proxy target is extensible")
        }
        return r
    }

    public override func GetOwnProperty(_ key: PropertyKey) throws -> PropertyDescriptor? {
        let (t, h) = try parts("getOwnPropertyDescriptor")
        guard let tr = try trap(h, "getOwnPropertyDescriptor") else { return try t.GetOwnProperty(key) }
        let r = try tr.Call(.object(h), [.object(t), KeyToValue(key)])
        let targetDesc = try t.GetOwnProperty(key)
        if r.IsUndefined {
            guard let td = targetDesc else { return nil }
            if td.Configurable == false {
                throw ThrowTypeError("'getOwnPropertyDescriptor' on proxy: trap returned undefined for property '\(KeyDisplay(key))' which is non-configurable in the proxy target")
            }
            if !(try t.IsExtensibleObject()) {
                throw ThrowTypeError("'getOwnPropertyDescriptor' on proxy: trap returned undefined for property '\(KeyDisplay(key))' which exists in the non-extensible proxy target")
            }
            return nil
        }
        if !r.IsObject {
            throw ThrowTypeError("'getOwnPropertyDescriptor' on proxy: trap returned neither object nor undefined for property '\(KeyDisplay(key))'")
        }
        let ext = try t.IsExtensibleObject()
        let result = CompletePropertyDescriptor(try ToPropertyDescriptor(r))
        if !isCompatible(ext, result, targetDesc) {
            throw ThrowTypeError("'getOwnPropertyDescriptor' on proxy: trap returned descriptor for property '\(KeyDisplay(key))' that is incompatible with the existing property in the proxy target")
        }
        if result.Configurable == false {
            if targetDesc == nil || targetDesc!.Configurable == true {
                throw ThrowTypeError("'getOwnPropertyDescriptor' on proxy: trap reported non-configurability for property '\(KeyDisplay(key))' which is either non-existent or configurable in the proxy target")
            }
        }
        return result
    }

    func isCompatible(_ extensible: bool, _ desc: PropertyDescriptor, _ current: PropertyDescriptor?) -> bool {
        guard let cur = current else { return extensible }
        if cur.Configurable == false {
            if desc.Configurable == true { return false }
            if let e = desc.Enumerable, e != cur.Enumerable { return false }
            if !desc.IsGeneric && desc.IsAccessor != cur.IsAccessor { return false }
            if cur.IsAccessor {
                if let g = desc.Get, !SameValue(g, cur.Get ?? .undefined) { return false }
                if let s = desc.Set, !SameValue(s, cur.Set ?? .undefined) { return false }
            } else if cur.Writable == false {
                if desc.Writable == true { return false }
                if let v = desc.Value, !SameValue(v, cur.Value ?? .undefined) { return false }
            }
        }
        return true
    }

    public override func DefineOwnProperty(_ key: PropertyKey, _ desc: PropertyDescriptor) throws -> bool {
        let (t, h) = try parts("defineProperty")
        guard let tr = try trap(h, "defineProperty") else { return try t.DefineOwnProperty(key, desc) }
        let descObj = FromPropertyDescriptor(desc)
        if !(try tr.Call(.object(h), [.object(t), KeyToValue(key), descObj]).Truthy) { return false }
        let targetDesc = try t.GetOwnProperty(key)
        let ext = try t.IsExtensibleObject()
        let settingNonConfig = desc.Configurable == false
        if targetDesc == nil {
            if !ext { throw ThrowTypeError("'defineProperty' on proxy: trap returned truish for adding property '\(KeyDisplay(key))'  to the non-extensible proxy target") }
            if settingNonConfig { throw ThrowTypeError("'defineProperty' on proxy: trap returned truish for defining non-configurable property '\(KeyDisplay(key))' which is either non-existent or configurable in the proxy target") }
        } else {
            if !isCompatible(ext, desc, targetDesc) {
                throw ThrowTypeError("'defineProperty' on proxy: trap returned truish for adding property '\(KeyDisplay(key))'  that is incompatible with the existing property in the proxy target")
            }
            if settingNonConfig && targetDesc!.Configurable == true {
                throw ThrowTypeError("'defineProperty' on proxy: trap returned truish for defining non-configurable property '\(KeyDisplay(key))' which is either non-existent or configurable in the proxy target")
            }
        }
        return true
    }

    public override func HasProperty(_ key: PropertyKey) throws -> bool {
        let (t, h) = try parts("has")
        guard let tr = try trap(h, "has") else { return try t.HasProperty(key) }
        let r = try tr.Call(.object(h), [.object(t), KeyToValue(key)]).Truthy
        if !r {
            if let td = try t.GetOwnProperty(key) {
                if td.Configurable == false {
                    throw ThrowTypeError("'has' on proxy: trap returned falsish for property '\(KeyDisplay(key))' which exists in the proxy target as non-configurable")
                }
                if !(try t.IsExtensibleObject()) {
                    throw ThrowTypeError("'has' on proxy: trap returned falsish for property '\(KeyDisplay(key))' but the proxy target is not extensible")
                }
            }
        }
        return r
    }

    public override func Get(_ key: PropertyKey, _ receiver: Value) throws -> Value {
        let (t, h) = try parts("get")
        guard let tr = try trap(h, "get") else { return try t.Get(key, receiver) }
        let v = try tr.Call(.object(h), [.object(t), KeyToValue(key), receiver])
        if let td = try t.GetOwnProperty(key), td.Configurable == false {
            if td.IsData && td.Writable == false && !SameValue(v, td.Value ?? .undefined) {
                throw ThrowTypeError("'get' on proxy: property '\(KeyDisplay(key))' is a read-only and non-configurable data property on the proxy target but the proxy did not return its actual value")
            }
            if td.IsAccessor && (td.Get ?? .undefined).IsUndefined && !v.IsUndefined {
                throw ThrowTypeError("'get' on proxy: property '\(KeyDisplay(key))' is a non-configurable accessor property on the proxy target and does not have a getter function, but the trap did not return 'undefined'")
            }
        }
        return v
    }

    public override func Set(_ key: PropertyKey, _ v: Value, _ receiver: Value) throws -> bool {
        let (t, h) = try parts("set")
        guard let tr = try trap(h, "set") else { return try t.Set(key, v, receiver) }
        if !(try tr.Call(.object(h), [.object(t), KeyToValue(key), v, receiver]).Truthy) { return false }
        if let td = try t.GetOwnProperty(key), td.Configurable == false {
            if td.IsData && td.Writable == false && !SameValue(v, td.Value ?? .undefined) {
                throw ThrowTypeError("'set' on proxy: trap returned truish for property '\(KeyDisplay(key))' which exists in the proxy target as a non-configurable and non-writable data property with a different value")
            }
            if td.IsAccessor && (td.Set ?? .undefined).IsUndefined {
                throw ThrowTypeError("'set' on proxy: trap returned truish for property '\(KeyDisplay(key))' which exists in the proxy target as a non-configurable and non-writable accessor property without a setter")
            }
        }
        return true
    }

    public override func Delete(_ key: PropertyKey) throws -> bool {
        let (t, h) = try parts("deleteProperty")
        guard let tr = try trap(h, "deleteProperty") else { return try t.Delete(key) }
        if !(try tr.Call(.object(h), [.object(t), KeyToValue(key)]).Truthy) { return false }
        if let td = try t.GetOwnProperty(key) {
            if td.Configurable == false {
                throw ThrowTypeError("'deleteProperty' on proxy: trap returned truish for property '\(KeyDisplay(key))' which is non-configurable in the proxy target")
            }
            if !(try t.IsExtensibleObject()) {
                throw ThrowTypeError("'deleteProperty' on proxy: trap returned truish for property '\(KeyDisplay(key))' but the proxy target is non-extensible")
            }
        }
        return true
    }

    public override func OwnPropertyKeys() throws -> [PropertyKey] {
        let (t, h) = try parts("ownKeys")
        guard let tr = try trap(h, "ownKeys") else { return try t.OwnPropertyKeys() }
        let r = try tr.Call(.object(h), [.object(t)])
        guard case .object(let ro) = r else {
            throw ThrowTypeError("CreateListFromArrayLike called on non-object")
        }
        let list = try CreateListFromArrayLike(.object(ro))
        var keys: [PropertyKey] = []
        for v in list {
            switch v {
            case .string, .symbol:
                let k = try ToPropertyKey(v)
                for e in keys where e == k {
                    throw ThrowTypeError("'ownKeys' on proxy: trap returned duplicate entries")
                }
                keys.append(k)
            default:
                throw ThrowTypeError("\(Describe(v)) is not a valid property name")
            }
        }
        let ext = try t.IsExtensibleObject()
        let targetKeys = try t.OwnPropertyKeys()
        var nonconfig: [PropertyKey] = []
        var config: [PropertyKey] = []
        for k in targetKeys {
            if let d = try t.GetOwnProperty(k), d.Configurable == false { nonconfig.append(k) } else { config.append(k) }
        }
        if ext && nonconfig.isEmpty { return keys }
        var unchecked = keys
        for k in nonconfig {
            var found = -1
            var i = 0
            while i < unchecked.count { if unchecked[i] == k { found = i; break }; i += 1 }
            if found < 0 {
                throw ThrowTypeError("'ownKeys' on proxy: trap result did not include '\(KeyDisplay(k))'")
            }
            unchecked.remove(at: found)
        }
        if ext { return keys }
        for k in config {
            var found = -1
            var i = 0
            while i < unchecked.count { if unchecked[i] == k { found = i; break }; i += 1 }
            if found < 0 {
                throw ThrowTypeError("'ownKeys' on proxy: trap result did not include '\(KeyDisplay(k))'")
            }
            unchecked.remove(at: found)
        }
        if !unchecked.isEmpty {
            throw ThrowTypeError("'ownKeys' on proxy: trap returned extra keys but proxy target is non-extensible")
        }
        return keys
    }

    public override func Call(_ this: Value, _ args: [Value]) throws -> Value {
        let (t, h) = try parts("apply")
        guard let tr = try trap(h, "apply") else { return try t.Call(this, args) }
        let arr = CreateArrayFromList(CurrentRealm(), args)
        return try tr.Call(.object(h), [.object(t), this, .object(arr)])
    }

    public override func Construct(_ args: [Value], _ newTarget: JSObject) throws -> Value {
        let (t, h) = try parts("construct")
        guard let tr = try trap(h, "construct") else { return try t.Construct(args, newTarget) }
        let arr = CreateArrayFromList(CurrentRealm(), args)
        let r = try tr.Call(.object(h), [.object(t), .object(arr), .object(newTarget)])
        if !r.IsObject {
            throw ThrowTypeError("proxy [[Construct]] must return an object")
        }
        return r
    }
}

let unusedProxyKey = value.SymIterator
