package indexed

import (
    "js/object"
    "js/value"
)

/// Register registers Array built-in (§23) into the realm.
public func Register(into realm: object.Realm) {
    let g = realm.GlobalObject
    let proto = realm.ArrayPrototype

    // Array constructor
    let arrayCtor = realm.NewFunction(name: "Array") { r, _, args in
        if args.count == 1 && args[0].IsNumber {
            let len = Int(args[0].ToInt32())
            let arr = r.NewArray()
            arr.Set("length", value.Value.Int(int32(len)))
            return value.Value.Object(arr)
        }
        let arr = r.NewArray(elements: args)
        return value.Value.Object(arr)
    }
    arrayCtor.Set("prototype", value.Value.Object(proto))

    // Array.isArray
    let isArrayFn = realm.NewFunction(name: "isArray") { _, _, args in
        if args.isEmpty || !args[0].IsObject { return value.Value.False }
        if let obj = args[0].ObjVal as? object.JSObject {
            return value.Value.Boolean(obj.InternalTag == "Array")
        }
        return value.Value.False
    }
    arrayCtor.Set("isArray", value.Value.Object(isArrayFn))

    // push
    proto.Set("push", value.Value.Object(realm.NewFunction(name: "push") { _, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return value.Value.Int(0) }
        for a in args {
            arr.SetElement(arr.Elements.count, a)
        }
        return value.Value.Int(int32(arr.Elements.count))
    }))

    // pop
    proto.Set("pop", value.Value.Object(realm.NewFunction(name: "pop") { _, thisVal, _ in
        guard let arr = thisVal.ObjVal as? object.JSObject, !arr.Elements.isEmpty else { return value.Value.Undefined }
        let el = arr.Elements.removeLast()
        arr.Set("length", value.Value.Int(int32(arr.Elements.count)))
        return el
    }))

    // shift
    proto.Set("shift", value.Value.Object(realm.NewFunction(name: "shift") { _, thisVal, _ in
        guard let arr = thisVal.ObjVal as? object.JSObject, !arr.Elements.isEmpty else { return value.Value.Undefined }
        let el = arr.Elements.remove(at: 0)
        arr.Set("length", value.Value.Int(int32(arr.Elements.count)))
        return el
    }))

    // unshift
    proto.Set("unshift", value.Value.Object(realm.NewFunction(name: "unshift") { _, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return value.Value.Int(0) }
        for i in (0..<args.count).reversed() {
            arr.Elements.insert(args[i], at: 0)
        }
        arr.Set("length", value.Value.Int(int32(arr.Elements.count)))
        return value.Value.Int(int32(arr.Elements.count))
    }))

    // join
    proto.Set("join", value.Value.Object(realm.NewFunction(name: "join") { _, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return value.Value.String("") }
        let sep = args.isEmpty ? "," : args[0].ToString()
        var parts: [string] = []
        for el in arr.Elements {
            parts.append(el.IsNullOrUndefined ? "" : el.ToString())
        }
        return value.Value.String(parts.joined(separator: sep))
    }))

    // reverse
    proto.Set("reverse", value.Value.Object(realm.NewFunction(name: "reverse") { _, thisVal, _ in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return thisVal }
        var i = 0
        var j = arr.Elements.count - 1
        while i < j {
            let tmp = arr.Elements[i]
            arr.Elements[i] = arr.Elements[j]
            arr.Elements[j] = tmp
            i += 1
            j -= 1
        }
        return thisVal
    }))

    // slice
    proto.Set("slice", value.Value.Object(realm.NewFunction(name: "slice") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return value.Value.Object(r.NewArray()) }
        let len = arr.Elements.count
        var start = args.isEmpty ? 0 : Int(args[0].ToInt32())
        if start < 0 { start = len + start; if start < 0 { start = 0 } }
        else if start > len { start = len }

        var end = len
        if args.count > 1 && !args[1].IsUndefined {
            end = Int(args[1].ToInt32())
            if end < 0 { end = len + end; if end < 0 { end = 0 } }
            else if end > len { end = len }
        }
        var sub: [value.Value] = []
        if start < end {
            for i in start..<end {
                sub.append(arr.Elements[i])
            }
        }
        return value.Value.Object(r.NewArray(elements: sub))
    }))

    // indexOf
    proto.Set("indexOf", value.Value.Object(realm.NewFunction(name: "indexOf") { _, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject, !args.isEmpty else { return value.Value.Int(-1) }
        let target = args[0]
        var from = 0
        if args.count > 1 {
            from = Int(args[1].ToInt32())
            if from < 0 { from = arr.Elements.count + from; if from < 0 { from = 0 } }
        }
        for i in from..<arr.Elements.count {
            if value.StrictEquals(arr.Elements[i], target) {
                return value.Value.Int(int32(i))
            }
        }
        return value.Value.Int(-1)
    }))

    // includes
    proto.Set("includes", value.Value.Object(realm.NewFunction(name: "includes") { _, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject, !args.isEmpty else { return value.Value.False }
        let target = args[0]
        for el in arr.Elements {
            if value.StrictEquals(el, target) {
                return value.Value.True
            }
        }
        return value.Value.False
    }))

    g.Set("Array", value.Value.Object(arrayCtor))
}
