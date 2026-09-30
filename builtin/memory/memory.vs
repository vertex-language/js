// Package memory installs managing memory (ECMA-262 §26): WeakRef and
// FinalizationRegistry.
//
// TODO(gc): the engine has no tracing collector yet -- objects are
// reference counted -- so there is no collection to observe: a WeakRef
// holds its target strongly and cleanup callbacks never run (which the
// spec permits). A collector of the engine's own will make them weak.
package memory

import (
    "js/builtin/keyed"
    "js/object"
    "js/str"
    "js/value"
)

typealias Value = object.Value

func key(_ s: string) -> value.PropertyKey { return value.PropertyKey.Named(s) }

public final class WeakRef: object.JSObject {
    public let Target: Value
    public init(_ t: Value, proto: object.JSObject) {
        self.Target = t
        super.init(proto: proto)
        self.Kind = .weakRef
    }
}

public final class FinalizationRegistry: object.JSObject {
    public let Cleanup: Value
    public var Cells: [(target: Value, held: Value, token: Value)] = []
    public init(_ cleanup: Value, proto: object.JSObject) {
        self.Cleanup = cleanup
        super.init(proto: proto)
        self.Kind = .finalizationRegistry
    }
}

/// Install defines WeakRef and FinalizationRegistry.
public func Install(_ r: object.Realm) {
    let wrp = object.JSObject(proto: r.ObjectPrototype)
    _ = r.Constructor("WeakRef", 1, prototype: wrp) { _, args, nt in
        guard let n = nt else { throw object.ThrowTypeError("Constructor WeakRef requires 'new'") }
        let t = object.Arg(args, 0)
        if !keyed.CanBeHeldWeakly(t) { throw object.ThrowTypeError("WeakRef: invalid target") }
        return .object(WeakRef(t, proto: try object.GetPrototypeFromConstructor(n, wrp)))
    }
    r.Method(wrp, "deref", 0) { thisV, _, _ in
        guard case .object(let o) = thisV, let w = o as? WeakRef else {
            throw object.ThrowTypeError("Method WeakRef.prototype.deref called on incompatible receiver \(object.Describe(thisV))")
        }
        return w.Target
    }
    wrp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("WeakRef")), writable: false, enumerable: false, configurable: true)

    let frp = object.JSObject(proto: r.ObjectPrototype)
    _ = r.Constructor("FinalizationRegistry", 1, prototype: frp) { _, args, nt in
        guard let n = nt else { throw object.ThrowTypeError("Constructor FinalizationRegistry requires 'new'") }
        let cb = object.Arg(args, 0)
        if !cb.IsCallable { throw object.ThrowTypeError("FinalizationRegistry: cleanup must be callable") }
        return .object(FinalizationRegistry(cb, proto: try object.GetPrototypeFromConstructor(n, frp)))
    }
    func this(_ v: Value, _ method: string) throws -> FinalizationRegistry {
        if case .object(let o) = v, let f = o as? FinalizationRegistry { return f }
        throw object.ThrowTypeError("Method FinalizationRegistry.prototype.\(method) called on incompatible receiver \(object.Describe(v))")
    }
    r.Method(frp, "register", 2) { thisV, args, _ in
        let f = try this(thisV, "register")
        let t = object.Arg(args, 0)
        if !keyed.CanBeHeldWeakly(t) { throw object.ThrowTypeError("FinalizationRegistry.prototype.register: invalid target") }
        let held = object.Arg(args, 1)
        if object.SameValue(t, held) { throw object.ThrowTypeError("FinalizationRegistry.prototype.register: target and holdings must not be same") }
        let token = object.Arg(args, 2)
        if !token.IsUndefined && !keyed.CanBeHeldWeakly(token) {
            throw object.ThrowTypeError("FinalizationRegistry.prototype.register: invalid unregister token")
        }
        f.Cells.append((target: .undefined, held: held, token: token))
        return .undefined
    }
    r.Method(frp, "unregister", 1) { thisV, args, _ in
        let f = try this(thisV, "unregister")
        let token = object.Arg(args, 0)
        if !keyed.CanBeHeldWeakly(token) { throw object.ThrowTypeError("Invalid unregisterToken ('\(object.Describe(token))')") }
        let before = f.Cells.count
        f.Cells.removeAll { c in object.SameValue(c.token, token) }
        return .bool(f.Cells.count != before)
    }
    frp.DefineData(.symbol(value.SymToStringTag), .string(str.Name("FinalizationRegistry")), writable: false, enumerable: false, configurable: true)
}
