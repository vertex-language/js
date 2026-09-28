package memory

import (
    "gc"
    "js/object"
    "js/value"
)

final class ValueBox {
    var val: value.Value
    init(_ val: value.Value) { self.val = val }
}

final class WeakRefHolder {
    let weakRef: gc.WeakRef<gc.Cell>

    init(_ target: gc.Cell) {
        self.weakRef = gc.WeakRef(target)
    }
}

final class FinalizerHolder {
    let registry: gc.FinalizationRegistry
    let callback: object.JSObject

    init(reg: gc.FinalizationRegistry, cb: object.JSObject) {
        self.registry = reg
        self.callback = cb
    }
}

/// Register registers WeakRef and FinalizationRegistry built-ins (§26) into the realm.
public func Register(into realm: object.Realm) {
    let g = realm.GlobalObject

    // WeakRef
    let weakRefProto = realm.NewObject()
    weakRefProto.InternalTag = "WeakRef"

    let weakRefCtor = realm.NewFunction(name: "WeakRef") { r, _, args in
        guard !args.isEmpty, let target = args[0].ObjVal else {
            return value.Value.Undefined
        }
        let holder = WeakRefHolder(target)
        r.Heap.RegisterWeakRef(holder.weakRef)

        let wr = r.NewObject(prototype: weakRefProto)
        wr.InternalTag = "WeakRef"
        wr.NativeData = holder
        return value.Value.Object(wr)
    }
    weakRefCtor.Set("prototype", value.Value.Object(weakRefProto))

    weakRefProto.Set("deref", value.Value.Object(realm.NewFunction(name: "deref") { _, thisVal, _ in
        guard let wr = thisVal.ObjVal as? object.JSObject, let holder = wr.NativeData as? WeakRefHolder else {
            return value.Value.Undefined
        }
        if let target = holder.weakRef.Deref() {
            return value.Value.Object(target)
        }
        return value.Value.Undefined
    }))

    g.Set("WeakRef", value.Value.Object(weakRefCtor))

    // FinalizationRegistry
    let finProto = realm.NewObject()
    finProto.InternalTag = "FinalizationRegistry"

    let finCtor = realm.NewFunction(name: "FinalizationRegistry") { r, _, args in
        guard !args.isEmpty, let cb = args[0].ObjVal as? object.JSObject else {
            return value.Value.Undefined
        }
        let reg = gc.FinalizationRegistry()
        r.Heap.RegisterFinalizer(reg)

        let holder = FinalizerHolder(reg: reg, cb: cb)
        let regObj = r.NewObject(prototype: finProto)
        regObj.InternalTag = "FinalizationRegistry"
        regObj.NativeData = holder
        return value.Value.Object(regObj)
    }
    finCtor.Set("prototype", value.Value.Object(finProto))

    finProto.Set("register", value.Value.Object(realm.NewFunction(name: "register") { _, thisVal, args in
        guard let regObj = thisVal.ObjVal as? object.JSObject, let holder = regObj.NativeData as? FinalizerHolder else {
            return value.Value.Undefined
        }
        guard !args.isEmpty, let target = args[0].ObjVal else {
            return value.Value.Undefined
        }
        let heldVal = args.count > 1 ? args[1] : value.Value.Undefined
        let heldBox = ValueBox(heldVal)
        var unregToken: AnyObject? = nil
        if args.count > 2 {
            unregToken = args[2].ObjVal
        }

        holder.registry.Register(target: target, heldValue: heldBox, unregisterToken: unregToken) { _ in
            // Reclaimed target callback
        }
        return value.Value.Undefined
    }))

    finProto.Set("unregister", value.Value.Object(realm.NewFunction(name: "unregister") { _, thisVal, args in
        guard let regObj = thisVal.ObjVal as? object.JSObject, let holder = regObj.NativeData as? FinalizerHolder else {
            return value.Value.False
        }
        if args.isEmpty || args[0].ObjVal == nil {
            return value.Value.False
        }
        let ok = holder.registry.Unregister(token: args[0].ObjVal!)
        return value.Value.Boolean(ok)
    }))

    g.Set("FinalizationRegistry", value.Value.Object(finCtor))
}
