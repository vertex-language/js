package keyed

import (
    "gc"
    "js/object"
    "js/value"
)

final class WeakMapEntry {
    weak var keyCell: gc.Cell?
    var val: value.Value
    var ephemeron: gc.Ephemeron

    init(key: gc.Cell, val: value.Value, ephemeron: gc.Ephemeron) {
        self.keyCell = key
        self.val = val
        self.ephemeron = ephemeron
    }
}

public final class WeakMapRecord {
    var entries: [WeakMapEntry] = []

    public init() {}

    public func Set(key: gc.Cell, val: value.Value, heap: gc.Heap) {
        for e in entries {
            if e.ephemeron.IsActive, let k = e.keyCell, k === key {
                e.val = val
                e.ephemeron.Value = val.ObjVal as? gc.Cell
                return
            }
        }
        let valCell = val.ObjVal as? gc.Cell
        let eph = heap.Ephemerons.RegisterPair(key: key, value: valCell)
        entries.append(WeakMapEntry(key: key, val: val, ephemeron: eph))
    }

    public func Get(key: gc.Cell) -> value.Value {
        cleanDead()
        for e in entries {
            if e.ephemeron.IsActive, let k = e.keyCell, k === key {
                return e.val
            }
        }
        return value.Value.Undefined
    }

    public func Has(key: gc.Cell) -> bool {
        cleanDead()
        for e in entries {
            if e.ephemeron.IsActive, let k = e.keyCell, k === key {
                return true
            }
        }
        return false
    }

    public func Delete(key: gc.Cell) -> bool {
        for i in 0..<entries.count {
            let e = entries[i]
            if let k = e.keyCell, k === key {
                e.ephemeron.Clear()
                entries.remove(at: i)
                return true
            }
        }
        return false
    }

    func cleanDead() {
        var alive: [WeakMapEntry] = []
        for e in entries {
            if e.ephemeron.IsActive && e.keyCell != nil {
                alive.append(e)
            }
        }
        entries = alive
    }
}

/// Register registers Map, Set, WeakMap, and WeakSet built-ins (§24) into the realm.
public func Register(into realm: object.Realm) {
    let g = realm.GlobalObject

    // Map
    let mapProto = realm.NewObject()
    mapProto.InternalTag = "Map"

    let mapCtor = realm.NewFunction(name: "Map") { r, _, _ in
        let m = r.NewObject(prototype: mapProto)
        m.InternalTag = "Map"
        m.Set("size", value.Value.Int(0))
        return value.Value.Object(m)
    }
    mapCtor.Set("prototype", value.Value.Object(mapProto))

    mapProto.Set("set", value.Value.Object(realm.NewFunction(name: "set") { _, thisVal, args in
        guard let m = thisVal.ObjVal as? object.JSObject, !args.isEmpty else { return thisVal }
        let key = args[0].ToString()
        let val = args.count > 1 ? args[1] : value.Value.Undefined
        let hadKey = m.Has(key)
        m.Set(key, val)
        if !hadKey {
            let curSize = m.Get("size").ToInt32()
            m.Set("size", value.Value.Int(curSize + 1))
        }
        return thisVal
    }))

    mapProto.Set("get", value.Value.Object(realm.NewFunction(name: "get") { _, thisVal, args in
        guard let m = thisVal.ObjVal as? object.JSObject, !args.isEmpty else { return value.Value.Undefined }
        let key = args[0].ToString()
        return m.Get(key)
    }))

    mapProto.Set("has", value.Value.Object(realm.NewFunction(name: "has") { _, thisVal, args in
        guard let m = thisVal.ObjVal as? object.JSObject, !args.isEmpty else { return value.Value.False }
        let key = args[0].ToString()
        return value.Value.Boolean(m.Has(key))
    }))

    g.Set("Map", value.Value.Object(mapCtor))

    // Set
    let setProto = realm.NewObject()
    setProto.InternalTag = "Set"

    let setCtor = realm.NewFunction(name: "Set") { r, _, _ in
        let s = r.NewObject(prototype: setProto)
        s.InternalTag = "Set"
        s.Set("size", value.Value.Int(0))
        return value.Value.Object(s)
    }
    setCtor.Set("prototype", value.Value.Object(setProto))

    setProto.Set("add", value.Value.Object(realm.NewFunction(name: "add") { _, thisVal, args in
        guard let s = thisVal.ObjVal as? object.JSObject, !args.isEmpty else { return thisVal }
        let key = args[0].ToString()
        if !s.Has(key) {
            s.Set(key, value.Value.True)
            let curSize = s.Get("size").ToInt32()
            s.Set("size", value.Value.Int(curSize + 1))
        }
        return thisVal
    }))

    setProto.Set("has", value.Value.Object(realm.NewFunction(name: "has") { _, thisVal, args in
        guard let s = thisVal.ObjVal as? object.JSObject, !args.isEmpty else { return value.Value.False }
        let key = args[0].ToString()
        return value.Value.Boolean(s.Has(key))
    }))

    g.Set("Set", value.Value.Object(setCtor))

    // WeakMap
    let weakMapProto = realm.NewObject()
    weakMapProto.InternalTag = "WeakMap"

    let weakMapCtor = realm.NewFunction(name: "WeakMap") { r, _, _ in
        let wm = r.NewObject(prototype: weakMapProto)
        wm.InternalTag = "WeakMap"
        wm.NativeData = WeakMapRecord()
        return value.Value.Object(wm)
    }
    weakMapCtor.Set("prototype", value.Value.Object(weakMapProto))

    weakMapProto.Set("set", value.Value.Object(realm.NewFunction(name: "set") { r, thisVal, args in
        guard let wm = thisVal.ObjVal as? object.JSObject, let rec = wm.NativeData as? WeakMapRecord else { return thisVal }
        guard !args.isEmpty, let keyCell = args[0].ObjVal else {
            return thisVal
        }
        let val = args.count > 1 ? args[1] : value.Value.Undefined
        rec.Set(key: keyCell, val: val, heap: r.Heap)
        return thisVal
    }))

    weakMapProto.Set("get", value.Value.Object(realm.NewFunction(name: "get") { _, thisVal, args in
        guard let wm = thisVal.ObjVal as? object.JSObject, let rec = wm.NativeData as? WeakMapRecord else { return value.Value.Undefined }
        guard !args.isEmpty, let keyCell = args[0].ObjVal else {
            return value.Value.Undefined
        }
        return rec.Get(key: keyCell)
    }))

    weakMapProto.Set("has", value.Value.Object(realm.NewFunction(name: "has") { _, thisVal, args in
        guard let wm = thisVal.ObjVal as? object.JSObject, let rec = wm.NativeData as? WeakMapRecord else { return value.Value.False }
        guard !args.isEmpty, let keyCell = args[0].ObjVal else {
            return value.Value.False
        }
        return value.Value.Boolean(rec.Has(key: keyCell))
    }))

    weakMapProto.Set("delete", value.Value.Object(realm.NewFunction(name: "delete") { _, thisVal, args in
        guard let wm = thisVal.ObjVal as? object.JSObject, let rec = wm.NativeData as? WeakMapRecord else { return value.Value.False }
        guard !args.isEmpty, let keyCell = args[0].ObjVal else {
            return value.Value.False
        }
        return value.Value.Boolean(rec.Delete(key: keyCell))
    }))

    g.Set("WeakMap", value.Value.Object(weakMapCtor))

    // WeakSet
    let weakSetProto = realm.NewObject()
    weakSetProto.InternalTag = "WeakSet"

    let weakSetCtor = realm.NewFunction(name: "WeakSet") { r, _, _ in
        let ws = r.NewObject(prototype: weakSetProto)
        ws.InternalTag = "WeakSet"
        ws.NativeData = WeakMapRecord()
        return value.Value.Object(ws)
    }
    weakSetCtor.Set("prototype", value.Value.Object(weakSetProto))

    weakSetProto.Set("add", value.Value.Object(realm.NewFunction(name: "add") { r, thisVal, args in
        guard let ws = thisVal.ObjVal as? object.JSObject, let rec = ws.NativeData as? WeakMapRecord else { return thisVal }
        guard !args.isEmpty, let keyCell = args[0].ObjVal else {
            return thisVal
        }
        rec.Set(key: keyCell, val: value.Value.True, heap: r.Heap)
        return thisVal
    }))

    weakSetProto.Set("has", value.Value.Object(realm.NewFunction(name: "has") { _, thisVal, args in
        guard let ws = thisVal.ObjVal as? object.JSObject, let rec = ws.NativeData as? WeakMapRecord else { return value.Value.False }
        guard !args.isEmpty, let keyCell = args[0].ObjVal else {
            return value.Value.False
        }
        return value.Value.Boolean(rec.Has(key: keyCell))
    }))

    weakSetProto.Set("delete", value.Value.Object(realm.NewFunction(name: "delete") { _, thisVal, args in
        guard let ws = thisVal.ObjVal as? object.JSObject, let rec = ws.NativeData as? WeakMapRecord else { return value.Value.False }
        guard !args.isEmpty, let keyCell = args[0].ObjVal else {
            return value.Value.False
        }
        return value.Value.Boolean(rec.Delete(key: keyCell))
    }))

    g.Set("WeakSet", value.Value.Object(weakSetCtor))
}
