package fundamental

import (
    "js/object"
    "js/value"
)

/// Register registers fundamental objects (§20) into the realm.
public func Register(into realm: object.Realm) {
    let g = realm.GlobalObject

    // Object constructor
    let objectCtor = realm.NewFunction(name: "Object") { r, _, args in
        if args.isEmpty || args[0].IsNullOrUndefined {
            return value.Value.Object(r.NewObject())
        }
        if args[0].IsObject {
            return args[0]
        }
        return value.Value.Object(r.NewObject())
    }
    objectCtor.Set("prototype", value.Value.Object(realm.ObjectPrototype))

    // Object.keys
    let keysFn = realm.NewFunction(name: "keys") { r, _, args in
        let arr = r.NewArray()
        if args.isEmpty || !args[0].IsObject { return value.Value.Object(arr) }
        if let obj = args[0].ObjVal as? object.JSObject {
            let k = obj.Keys
            for i in 0..<k.count {
                arr.SetElement(i, value.Value.String(k[i]))
            }
        }
        return value.Value.Object(arr)
    }
    objectCtor.Set("keys", value.Value.Object(keysFn))

    // Object.values
    let valuesFn = realm.NewFunction(name: "values") { r, _, args in
        let arr = r.NewArray()
        if args.isEmpty || !args[0].IsObject { return value.Value.Object(arr) }
        if let obj = args[0].ObjVal as? object.JSObject {
            let k = obj.Keys
            for i in 0..<k.count {
                arr.SetElement(i, obj.Get(k[i]))
            }
        }
        return value.Value.Object(arr)
    }
    objectCtor.Set("values", value.Value.Object(valuesFn))

    // Object.assign
    let assignFn = realm.NewFunction(name: "assign") { _, _, args in
        if args.isEmpty { return value.Value.Undefined }
        let targetVal = args[0]
        guard let target = targetVal.ObjVal as? object.JSObject else { return targetVal }
        for i in 1..<args.count {
            if let src = args[i].ObjVal as? object.JSObject {
                for key in src.Keys {
                    target.Set(key, src.Get(key))
                }
            }
        }
        return targetVal
    }
    objectCtor.Set("assign", value.Value.Object(assignFn))

    // Object.create
    let createFn = realm.NewFunction(name: "create") { r, _, args in
        if args.isEmpty { return value.Value.Object(r.NewObject()) }
        let protoVal = args[0]
        if protoVal.IsNull {
            let obj = r.NewObject(prototype: nil)
            return value.Value.Object(obj)
        }
        if let protoObj = protoVal.ObjVal as? object.JSObject {
            let obj = r.NewObject(prototype: protoObj)
            return value.Value.Object(obj)
        }
        return value.Value.Object(r.NewObject())
    }
    objectCtor.Set("create", value.Value.Object(createFn))

    // Object.setPrototypeOf
    let setProtoFn = realm.NewFunction(name: "setPrototypeOf") { _, _, args in
        if args.count < 2 { return args.isEmpty ? value.Value.Undefined : args[0] }
        let target = args[0]
        let proto = args[1]
        guard let obj = target.ObjVal as? object.JSObject else { return target }
        if proto.IsNull {
            obj.Prototype = nil
        } else if let p = proto.ObjVal as? object.JSObject {
            obj.Prototype = p
        }
        return target
    }
    objectCtor.Set("setPrototypeOf", value.Value.Object(setProtoFn))

    // Object.getPrototypeOf
    let getProtoFn = realm.NewFunction(name: "getPrototypeOf") { _, _, args in
        if args.isEmpty || !args[0].IsObject { return value.Value.Undefined }
        if let obj = args[0].ObjVal as? object.JSObject, let p = obj.Prototype {
            return value.Value.Object(p)
        }
        return value.Value.Null
    }
    objectCtor.Set("getPrototypeOf", value.Value.Object(getProtoFn))

    g.Set("Object", value.Value.Object(objectCtor))

    // Object.prototype.toString
    let toStringFn = realm.NewFunction(name: "toString") { _, thisVal, _ in
        if let obj = thisVal.ObjVal as? object.JSObject {
            return value.Value.String("[object \(obj.InternalTag)]")
        }
        return value.Value.String("[object \(thisVal.Type)]")
    }
    realm.ObjectPrototype.Set("toString", value.Value.Object(toStringFn))

    // Object.prototype.valueOf
    let valueOfFn = realm.NewFunction(name: "valueOf") { _, thisVal, _ in
        return thisVal
    }
    realm.ObjectPrototype.Set("valueOf", value.Value.Object(valueOfFn))

    // Boolean constructor
    let boolCtor = realm.NewFunction(name: "Boolean") { _, _, args in
        let b = args.isEmpty ? false : args[0].ToBoolean()
        return value.Value.Boolean(b)
    }
    g.Set("Boolean", value.Value.Object(boolCtor))

    // Error constructor
    let errorCtor = realm.NewFunction(name: "Error") { r, _, args in
        let err = r.NewObject(prototype: r.ErrorPrototype)
        err.InternalTag = "Error"
        let msg = args.isEmpty ? "" : args[0].ToString()
        err.Set("message", value.Value.String(msg))
        return value.Value.Object(err)
    }
    errorCtor.Set("prototype", value.Value.Object(realm.ErrorPrototype))
    g.Set("Error", value.Value.Object(errorCtor))

    // TypeError constructor
    let typeErrorCtor = realm.NewFunction(name: "TypeError") { r, _, args in
        let err = r.NewObject(prototype: r.ErrorPrototype)
        err.InternalTag = "TypeError"
        let msg = args.isEmpty ? "" : args[0].ToString()
        err.Set("name", value.Value.String("TypeError"))
        err.Set("message", value.Value.String(msg))
        return value.Value.Object(err)
    }
    g.Set("TypeError", value.Value.Object(typeErrorCtor))
}
