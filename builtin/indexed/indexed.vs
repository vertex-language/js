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

    // Array.from (§23.1.2.1)
    let fromFn = realm.NewFunction(name: "from") { r, _, args in
        let out = r.NewArray()
        if args.isEmpty { return value.Value.Object(out) }
        var hasMap = false
        var mapFnObj: object.JSObject? = nil
        if args.count > 1, let mf = args[1].ObjVal as? object.JSObject {
            if mf.Callable != nil {
                hasMap = true
                mapFnObj = mf
            }
        }
        if let iterObj = args[0].ObjVal as? object.JSObject {
            for i in 0..<iterObj.Elements.count {
                var el = iterObj.Elements[i]
                if hasMap, let mf = mapFnObj {
                    el = try r.Call(mf, args: [el, value.Value.Int(int32(i))])
                }
                out.SetElement(i, el)
            }
        } else if args[0].IsString {
            let str = args[0].ToString()
            var idx = 0
            for ch in str {
                var el = value.Value.String(String(ch))
                if hasMap, let mf = mapFnObj {
                    el = try r.Call(mf, args: [el, value.Value.Int(int32(idx))])
                }
                out.SetElement(idx, el)
                idx += 1
            }
        }
        return value.Value.Object(out)
    }
    arrayCtor.Set("from", value.Value.Object(fromFn))

    // Array.of (§23.1.2.3)
    let ofFn = realm.NewFunction(name: "of") { r, _, args in
        return value.Value.Object(r.NewArray(elements: args))
    }
    arrayCtor.Set("of", value.Value.Object(ofFn))

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

    // at (§23.1.3.1)
    proto.Set("at", value.Value.Object(realm.NewFunction(name: "at") { _, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject, !args.isEmpty else { return value.Value.Undefined }
        var idx = Int(args[0].ToInt32())
        let len = arr.Elements.count
        if idx < 0 { idx = len + idx }
        if idx >= 0 && idx < len {
            return arr.Elements[idx]
        }
        return value.Value.Undefined
    }))

    // toReversed (ECMA-262 §23.1.3.33)
    proto.Set("toReversed", value.Value.Object(realm.NewFunction(name: "toReversed") { r, thisVal, _ in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return value.Value.Object(r.NewArray()) }
        let rev = Array(arr.Elements.reversed())
        return value.Value.Object(r.NewArray(elements: rev))
    }))

    // toSorted (ECMA-262 §23.1.3.34)
    proto.Set("toSorted", value.Value.Object(realm.NewFunction(name: "toSorted") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return value.Value.Object(r.NewArray()) }
        var copy = arr.Elements
        var hasCmp = false
        var cmpFnObj: object.JSObject? = nil
        if !args.isEmpty, let fn = args[0].ObjVal as? object.JSObject {
            if fn.Callable != nil {
                hasCmp = true
                cmpFnObj = fn
            }
        }
        if hasCmp, let fn = cmpFnObj {
            for i in 1..<copy.count {
                var j = i
                while j > 0 {
                    let cmpVal = try r.Call(fn, args: [copy[j - 1], copy[j]])
                    if cmpVal.ToNumber() > 0 {
                        copy.swapAt(j - 1, j)
                        j -= 1
                    } else {
                        break
                    }
                }
            }
        } else {
            copy.sort { $0.ToString() < $1.ToString() }
        }
        return value.Value.Object(r.NewArray(elements: copy))
    }))

    // toSpliced (ECMA-262 §23.1.3.35)
    proto.Set("toSpliced", value.Value.Object(realm.NewFunction(name: "toSpliced") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return value.Value.Object(r.NewArray()) }
        let copy = arr.Elements
        let len = copy.count
        var start = args.isEmpty ? 0 : Int(args[0].ToInt32())
        if start < 0 { start = len + start; if start < 0 { start = 0 } }
        else if start > len { start = len }

        var delCount = args.count > 1 ? Int(args[1].ToInt32()) : (len - start)
        if delCount < 0 { delCount = 0 }
        if start + delCount > len { delCount = len - start }

        var insertItems: [value.Value] = []
        if args.count > 2 {
            for i in 2..<args.count {
                insertItems.append(args[i])
            }
        }
        var newElems: [value.Value] = []
        for i in 0..<start { newElems.append(copy[i]) }
        for it in insertItems { newElems.append(it) }
        for i in (start + delCount)..<len { newElems.append(copy[i]) }
        return value.Value.Object(r.NewArray(elements: newElems))
    }))

    // with (ECMA-262 §23.1.3.37)
    proto.Set("with", value.Value.Object(realm.NewFunction(name: "with") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return value.Value.Object(r.NewArray()) }
        let len = arr.Elements.count
        if args.isEmpty { return value.Value.Object(r.NewArray(elements: arr.Elements)) }
        var idx = Int(args[0].ToInt32())
        if idx < 0 { idx = len + idx }
        if idx < 0 || idx >= len {
            throw object.RuntimeError.error("RangeError: Invalid index in Array.prototype.with")
        }
        var copy = arr.Elements
        copy[idx] = args.count > 1 ? args[1] : value.Value.Undefined
        return value.Value.Object(r.NewArray(elements: copy))
    }))

    // findLast (ECMA-262 §23.1.3.14)
    proto.Set("findLast", value.Value.Object(realm.NewFunction(name: "findLast") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject,
              !args.isEmpty,
              let fn = args[0].ObjVal as? object.JSObject,
              fn.Callable != nil else { return value.Value.Undefined }
        for i in (0..<arr.Elements.count).reversed() {
            let el = arr.Elements[i]
            let test = try r.Call(fn, args: [el, value.Value.Int(int32(i)), thisVal])
            if test.ToBoolean() { return el }
        }
        return value.Value.Undefined
    }))

    // findLastIndex (ECMA-262 §23.1.3.15)
    proto.Set("findLastIndex", value.Value.Object(realm.NewFunction(name: "findLastIndex") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject,
              !args.isEmpty,
              let fn = args[0].ObjVal as? object.JSObject,
              fn.Callable != nil else { return value.Value.Int(-1) }
        for i in (0..<arr.Elements.count).reversed() {
            let el = arr.Elements[i]
            let test = try r.Call(fn, args: [el, value.Value.Int(int32(i)), thisVal])
            if test.ToBoolean() { return value.Value.Int(int32(i)) }
        }
        return value.Value.Int(-1)
    }))

    // map (§23.1.3.19)
    proto.Set("map", value.Value.Object(realm.NewFunction(name: "map") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return value.Value.Object(r.NewArray()) }
        let out = r.NewArray()
        if args.isEmpty { return value.Value.Object(out) }
        guard let fn = args[0].ObjVal as? object.JSObject, fn.Callable != nil else { return value.Value.Object(out) }
        for i in 0..<arr.Elements.count {
            let res = try r.Call(fn, args: [arr.Elements[i], value.Value.Int(int32(i)), thisVal])
            out.SetElement(i, res)
        }
        return value.Value.Object(out)
    }))

    // filter (§23.1.3.8)
    proto.Set("filter", value.Value.Object(realm.NewFunction(name: "filter") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject else { return value.Value.Object(r.NewArray()) }
        let out = r.NewArray()
        if args.isEmpty { return value.Value.Object(out) }
        guard let fn = args[0].ObjVal as? object.JSObject, fn.Callable != nil else { return value.Value.Object(out) }
        for i in 0..<arr.Elements.count {
            let el = arr.Elements[i]
            let res = try r.Call(fn, args: [el, value.Value.Int(int32(i)), thisVal])
            if res.ToBoolean() {
                out.SetElement(out.Elements.count, el)
            }
        }
        return value.Value.Object(out)
    }))

    // forEach (§23.1.3.13)
    proto.Set("forEach", value.Value.Object(realm.NewFunction(name: "forEach") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject,
              !args.isEmpty,
              let fn = args[0].ObjVal as? object.JSObject,
              fn.Callable != nil else { return value.Value.Undefined }
        for i in 0..<arr.Elements.count {
            _ = try r.Call(fn, args: [arr.Elements[i], value.Value.Int(int32(i)), thisVal])
        }
        return value.Value.Undefined
    }))

    // reduce (§23.1.3.22)
    proto.Set("reduce", value.Value.Object(realm.NewFunction(name: "reduce") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject,
              !args.isEmpty,
              let fn = args[0].ObjVal as? object.JSObject,
              fn.Callable != nil else { return value.Value.Undefined }
        let len = arr.Elements.count
        var acc: value.Value
        var startIdx = 0
        if args.count > 1 {
            acc = args[1]
        } else if len > 0 {
            acc = arr.Elements[0]
            startIdx = 1
        } else {
            return value.Value.Undefined
        }
        for i in startIdx..<len {
            acc = try r.Call(fn, args: [acc, arr.Elements[i], value.Value.Int(int32(i)), thisVal])
        }
        return acc
    }))

    // find (§23.1.3.9)
    proto.Set("find", value.Value.Object(realm.NewFunction(name: "find") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject,
              !args.isEmpty,
              let fn = args[0].ObjVal as? object.JSObject,
              fn.Callable != nil else { return value.Value.Undefined }
        for i in 0..<arr.Elements.count {
            let el = arr.Elements[i]
            let test = try r.Call(fn, args: [el, value.Value.Int(int32(i)), thisVal])
            if test.ToBoolean() { return el }
        }
        return value.Value.Undefined
    }))

    // findIndex (§23.1.3.10)
    proto.Set("findIndex", value.Value.Object(realm.NewFunction(name: "findIndex") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject,
              !args.isEmpty,
              let fn = args[0].ObjVal as? object.JSObject,
              fn.Callable != nil else { return value.Value.Int(-1) }
        for i in 0..<arr.Elements.count {
            let test = try r.Call(fn, args: [arr.Elements[i], value.Value.Int(int32(i)), thisVal])
            if test.ToBoolean() { return value.Value.Int(int32(i)) }
        }
        return value.Value.Int(-1)
    }))

    // some (§23.1.3.27)
    proto.Set("some", value.Value.Object(realm.NewFunction(name: "some") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject,
              !args.isEmpty,
              let fn = args[0].ObjVal as? object.JSObject,
              fn.Callable != nil else { return value.Value.False }
        for i in 0..<arr.Elements.count {
            let test = try r.Call(fn, args: [arr.Elements[i], value.Value.Int(int32(i)), thisVal])
            if test.ToBoolean() { return value.Value.True }
        }
        return value.Value.False
    }))

    // every (§23.1.3.5)
    proto.Set("every", value.Value.Object(realm.NewFunction(name: "every") { r, thisVal, args in
        guard let arr = thisVal.ObjVal as? object.JSObject,
              !args.isEmpty,
              let fn = args[0].ObjVal as? object.JSObject,
              fn.Callable != nil else { return value.Value.True }
        for i in 0..<arr.Elements.count {
            let test = try r.Call(fn, args: [arr.Elements[i], value.Value.Int(int32(i)), thisVal])
            if !test.ToBoolean() { return value.Value.False }
        }
        return value.Value.True
    }))

    g.Set("Array", value.Value.Object(arrayCtor))
}
