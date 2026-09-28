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

    let mapCtor = realm.NewFunction(name: "Map") { r, _, args in
        let m = r.NewObject(prototype: mapProto)
        m.InternalTag = "Map"
        m.Set("size", value.Value.Int(0))
        if !args.isEmpty, let iterObj = args[0].ObjVal as? object.JSObject {
            for entryVal in iterObj.Elements {
                if let entry = entryVal.ObjVal as? object.JSObject, entry.Elements.count >= 2 {
                    let k = entry.Elements[0].ToString()
                    let v = entry.Elements[1]
                    if !m.Has(k) {
                        let curSize = m.Get("size").ToInt32()
                        m.Set("size", value.Value.Int(curSize + 1))
                    }
                    m.Set(k, v)
                }
            }
        }
        return value.Value.Object(m)
    }
    mapCtor.Set("prototype", value.Value.Object(mapProto))

    // Map.groupBy (§24.1.2.2)
    mapCtor.Set("groupBy", value.Value.Object(realm.NewFunction(name: "groupBy") { r, _, args in
        let mapObj = r.NewObject(prototype: mapProto)
        mapObj.InternalTag = "Map"
        mapObj.Set("size", value.Value.Int(0))
        if args.count < 2 { return value.Value.Object(mapObj) }
        guard let items = args[0].ObjVal as? object.JSObject,
              let callback = args[1].ObjVal as? object.JSObject,
              callback.Callable != nil else {
            return value.Value.Object(mapObj)
        }
        for i in 0..<items.Elements.count {
            let el = items.Elements[i]
            let keyVal = try r.Call(callback, args: [el, value.Value.Int(int32(i))])
            let groupKey = keyVal.ToString()
            let groupArr: object.JSObject
            if mapObj.Has(groupKey), let existing = mapObj.Get(groupKey).ObjVal as? object.JSObject {
                groupArr = existing
            } else {
                groupArr = r.NewArray()
                mapObj.Set(groupKey, value.Value.Object(groupArr))
                let curSize = mapObj.Get("size").ToInt32()
                mapObj.Set("size", value.Value.Int(curSize + 1))
            }
            groupArr.SetElement(groupArr.Elements.count, el)
        }
        return value.Value.Object(mapObj)
    }))

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

    mapProto.Set("delete", value.Value.Object(realm.NewFunction(name: "delete") { _, thisVal, args in
        guard let m = thisVal.ObjVal as? object.JSObject, !args.isEmpty else { return value.Value.False }
        let key = args[0].ToString()
        if m.Has(key) {
            m.Delete(key)
            let curSize = m.Get("size").ToInt32()
            if curSize > 0 { m.Set("size", value.Value.Int(curSize - 1)) }
            return value.Value.True
        }
        return value.Value.False
    }))

    mapProto.Set("clear", value.Value.Object(realm.NewFunction(name: "clear") { _, thisVal, _ in
        guard let m = thisVal.ObjVal as? object.JSObject else { return value.Value.Undefined }
        for k in m.Keys {
            if k != "size" { m.Delete(k) }
        }
        m.Set("size", value.Value.Int(0))
        return value.Value.Undefined
    }))

    g.Set("Map", value.Value.Object(mapCtor))

    // Set
    let setProto = realm.NewObject()
    setProto.InternalTag = "Set"

    let setCtor = realm.NewFunction(name: "Set") { r, _, args in
        let s = r.NewObject(prototype: setProto)
        s.InternalTag = "Set"
        s.Set("size", value.Value.Int(0))
        if !args.isEmpty, let iterObj = args[0].ObjVal as? object.JSObject {
            for el in iterObj.Elements {
                let k = el.ToString()
                if !s.Has(k) {
                    s.Set(k, value.Value.True)
                    let curSize = s.Get("size").ToInt32()
                    s.Set("size", value.Value.Int(curSize + 1))
                }
            }
        }
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

    setProto.Set("delete", value.Value.Object(realm.NewFunction(name: "delete") { _, thisVal, args in
        guard let s = thisVal.ObjVal as? object.JSObject, !args.isEmpty else { return value.Value.False }
        let key = args[0].ToString()
        if s.Has(key) {
            s.Delete(key)
            let curSize = s.Get("size").ToInt32()
            if curSize > 0 { s.Set("size", value.Value.Int(curSize - 1)) }
            return value.Value.True
        }
        return value.Value.False
    }))

    setProto.Set("clear", value.Value.Object(realm.NewFunction(name: "clear") { _, thisVal, _ in
        guard let s = thisVal.ObjVal as? object.JSObject else { return value.Value.Undefined }
        for k in s.Keys {
            if k != "size" { s.Delete(k) }
        }
        s.Set("size", value.Value.Int(0))
        return value.Value.Undefined
    }))

    // ES2025 Set methods (§24.2.3)
    let getSetKeys: (object.JSObject) -> [string] = { s in
        var res: [string] = []
        for k in s.Keys {
            if k != "size" { res.append(k) }
        }
        return res
    }

    setProto.Set("union", value.Value.Object(realm.NewFunction(name: "union") { r, thisVal, args in
        let res = r.NewObject(prototype: setProto)
        res.InternalTag = "Set"
        res.Set("size", value.Value.Int(0))
        if let s = thisVal.ObjVal as? object.JSObject {
            for k in getSetKeys(s) {
                res.Set(k, value.Value.True)
            }
        }
        if !args.isEmpty, let other = args[0].ObjVal as? object.JSObject {
            for k in getSetKeys(other) {
                res.Set(k, value.Value.True)
            }
        }
        let keys = getSetKeys(res)
        res.Set("size", value.Value.Int(int32(keys.count)))
        return value.Value.Object(res)
    }))

    setProto.Set("intersection", value.Value.Object(realm.NewFunction(name: "intersection") { r, thisVal, args in
        let res = r.NewObject(prototype: setProto)
        res.InternalTag = "Set"
        res.Set("size", value.Value.Int(0))
        guard let s = thisVal.ObjVal as? object.JSObject, !args.isEmpty, let other = args[0].ObjVal as? object.JSObject else {
            return value.Value.Object(res)
        }
        for k in getSetKeys(s) {
            if other.Has(k) {
                res.Set(k, value.Value.True)
            }
        }
        let keys = getSetKeys(res)
        res.Set("size", value.Value.Int(int32(keys.count)))
        return value.Value.Object(res)
    }))

    setProto.Set("difference", value.Value.Object(realm.NewFunction(name: "difference") { r, thisVal, args in
        let res = r.NewObject(prototype: setProto)
        res.InternalTag = "Set"
        res.Set("size", value.Value.Int(0))
        guard let s = thisVal.ObjVal as? object.JSObject else { return value.Value.Object(res) }
        var otherHas: [string: bool] = [:]
        if !args.isEmpty, let o = args[0].ObjVal as? object.JSObject {
            for k in getSetKeys(o) {
                otherHas[k] = true
            }
        }
        for k in getSetKeys(s) {
            if otherHas[k] != true {
                res.Set(k, value.Value.True)
            }
        }
        let keys = getSetKeys(res)
        res.Set("size", value.Value.Int(int32(keys.count)))
        return value.Value.Object(res)
    }))

    setProto.Set("symmetricDifference", value.Value.Object(realm.NewFunction(name: "symmetricDifference") { r, thisVal, args in
        let res = r.NewObject(prototype: setProto)
        res.InternalTag = "Set"
        res.Set("size", value.Value.Int(0))
        guard let s = thisVal.ObjVal as? object.JSObject else { return value.Value.Object(res) }
        var otherHas: [string: bool] = [:]
        if !args.isEmpty, let o = args[0].ObjVal as? object.JSObject {
            for k in getSetKeys(o) {
                otherHas[k] = true
            }
        }
        for k in getSetKeys(s) {
            if otherHas[k] != true {
                res.Set(k, value.Value.True)
            }
        }
        if !args.isEmpty, let o = args[0].ObjVal as? object.JSObject {
            for k in getSetKeys(o) {
                if !s.Has(k) {
                    res.Set(k, value.Value.True)
                }
            }
        }
        let keys = getSetKeys(res)
        res.Set("size", value.Value.Int(int32(keys.count)))
        return value.Value.Object(res)
    }))

    setProto.Set("isSubsetOf", value.Value.Object(realm.NewFunction(name: "isSubsetOf") { _, thisVal, args in
        guard let s = thisVal.ObjVal as? object.JSObject, !args.isEmpty, let other = args[0].ObjVal as? object.JSObject else {
            return value.Value.False
        }
        for k in getSetKeys(s) {
            if !other.Has(k) { return value.Value.False }
        }
        return value.Value.True
    }))

    setProto.Set("isSupersetOf", value.Value.Object(realm.NewFunction(name: "isSupersetOf") { _, thisVal, args in
        guard let s = thisVal.ObjVal as? object.JSObject, !args.isEmpty, let other = args[0].ObjVal as? object.JSObject else {
            return value.Value.False
        }
        for k in getSetKeys(other) {
            if !s.Has(k) { return value.Value.False }
        }
        return value.Value.True
    }))

    setProto.Set("isDisjointFrom", value.Value.Object(realm.NewFunction(name: "isDisjointFrom") { _, thisVal, args in
        guard let s = thisVal.ObjVal as? object.JSObject, !args.isEmpty, let other = args[0].ObjVal as? object.JSObject else {
            return value.Value.True
        }
        for k in getSetKeys(s) {
            if other.Has(k) { return value.Value.False }
        }
        return value.Value.True
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
