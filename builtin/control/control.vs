package control

import (
    "gc"
    "js/object"
    "js/value"
)

public final class PromiseCapability {
    public var promise: object.JSObject
    public init(promise: object.JSObject) {
        self.promise = promise
    }
}

public struct PromiseReaction {
    public var capability: PromiseCapability?
    public var handler: object.JSObject?
    public var isReject: bool

    public init(capability: PromiseCapability?, handler: object.JSObject?, isReject: bool) {
        self.capability = capability
        self.handler = handler
        self.isReject = isReject
    }
}

public final class PromiseRecord: gc.Cell {
    public var state: int = 0 // 0: pending, 1: fulfilled, 2: rejected
    public var result: value.Value = value.Value.Undefined
    public var fulfillReactions: [PromiseReaction] = []
    public var rejectReactions: [PromiseReaction] = []
    public var isHandled: bool = false

    public override func Trace(with tracer: gc.Tracer) {
        super.Trace(with: tracer)
        if result.Type == .object, let c = result.ObjVal as? gc.Cell {
            tracer.Visit(c)
        }
        for r in fulfillReactions {
            if let h = r.handler { tracer.Visit(h) }
            if let p = r.capability?.promise { tracer.Visit(p) }
        }
        for r in rejectReactions {
            if let h = r.handler { tracer.Visit(h) }
            if let p = r.capability?.promise { tracer.Visit(p) }
        }
    }
}

func newPromise(realm: object.Realm, prototype: object.JSObject) -> (object.JSObject, PromiseRecord) {
    let p = realm.NewObject(prototype: prototype)
    p.InternalTag = "Promise"
    let rec = PromiseRecord()
    p.NativeData = rec
    return (p, rec)
}

func triggerPromiseReaction(realm: object.Realm, reaction: PromiseReaction, argument: value.Value, isReject: bool) {
    if let h = reaction.handler, h.Callable != nil {
        do {
            let res = try realm.Call(h, args: [argument])
            if let cap = reaction.capability, let rec = cap.promise.NativeData as? PromiseRecord {
                resolvePromise(realm: realm, record: rec, promiseObj: cap.promise, resolution: res)
            }
        } catch {
            if let cap = reaction.capability, let rec = cap.promise.NativeData as? PromiseRecord {
                rejectPromise(realm: realm, record: rec, reason: value.Value.String("\(error)"))
            }
        }
    } else {
        if !isReject {
            if let cap = reaction.capability, let rec = cap.promise.NativeData as? PromiseRecord {
                resolvePromise(realm: realm, record: rec, promiseObj: cap.promise, resolution: argument)
            }
        } else {
            if let cap = reaction.capability, let rec = cap.promise.NativeData as? PromiseRecord {
                rejectPromise(realm: realm, record: rec, reason: argument)
            }
        }
    }
}

func fulfillPromise(realm: object.Realm, record: PromiseRecord, val: value.Value) {
    if record.state != 0 { return }
    record.state = 1
    record.result = val
    let reactions = record.fulfillReactions
    record.fulfillReactions = []
    record.rejectReactions = []

    for r in reactions {
        realm.EnqueueJob {
            triggerPromiseReaction(realm: realm, reaction: r, argument: val, isReject: false)
        }
    }
}

func rejectPromise(realm: object.Realm, record: PromiseRecord, reason: value.Value) {
    if record.state != 0 { return }
    record.state = 2
    record.result = reason
    let reactions = record.rejectReactions
    record.fulfillReactions = []
    record.rejectReactions = []

    for r in reactions {
        realm.EnqueueJob {
            triggerPromiseReaction(realm: realm, reaction: r, argument: reason, isReject: true)
        }
    }
}

func resolvePromise(realm: object.Realm, record: PromiseRecord, promiseObj: object.JSObject, resolution: value.Value) {
    if record.state != 0 { return }

    if resolution.IsObject, let resObj = resolution.ObjVal as? object.JSObject {
        if resObj === promiseObj {
            rejectPromise(realm: realm, record: record, reason: value.Value.String("TypeError: Chaining cycle detected for promise"))
            return
        }

        // Thenable check
        let thenProp = resObj.Get("then")
        if thenProp.IsObject, let thenFn = thenProp.ObjVal as? object.JSObject, thenFn.Callable != nil {
            var alreadyCalled = false
            let resolveFn = realm.NewFunction(name: "resolve") { r, _, args in
                if alreadyCalled { return value.Value.Undefined }
                alreadyCalled = true
                let arg = args.isEmpty ? value.Value.Undefined : args[0]
                resolvePromise(realm: r, record: record, promiseObj: promiseObj, resolution: arg)
                return value.Value.Undefined
            }
            let rejectFn = realm.NewFunction(name: "reject") { r, _, args in
                if alreadyCalled { return value.Value.Undefined }
                alreadyCalled = true
                let arg = args.isEmpty ? value.Value.Undefined : args[0]
                rejectPromise(realm: r, record: record, reason: arg)
                return value.Value.Undefined
            }

            realm.EnqueueJob {
                do {
                    _ = try realm.Call(thenFn, thisVal: resolution, args: [value.Value.Object(resolveFn), value.Value.Object(rejectFn)])
                } catch {
                    if !alreadyCalled {
                        alreadyCalled = true
                        rejectPromise(realm: realm, record: record, reason: value.Value.String("\(error)"))
                    }
                }
            }
            return
        }
    }

    fulfillPromise(realm: realm, record: record, val: resolution)
}

func createResolvingFunctions(realm: object.Realm, promiseObj: object.JSObject, record: PromiseRecord) -> (object.JSObject, object.JSObject) {
    var alreadyCalled = false

    let resolveFn = realm.NewFunction(name: "resolve") { r, _, args in
        if alreadyCalled { return value.Value.Undefined }
        alreadyCalled = true
        let arg = args.isEmpty ? value.Value.Undefined : args[0]
        resolvePromise(realm: r, record: record, promiseObj: promiseObj, resolution: arg)
        return value.Value.Undefined
    }

    let rejectFn = realm.NewFunction(name: "reject") { r, _, args in
        if alreadyCalled { return value.Value.Undefined }
        alreadyCalled = true
        let arg = args.isEmpty ? value.Value.Undefined : args[0]
        rejectPromise(realm: r, record: record, reason: arg)
        return value.Value.Undefined
    }

    return (resolveFn, rejectFn)
}

/// Register registers Promise (§27.2) and queueMicrotask into the realm.
public func Register(into realm: object.Realm) {
    let g = realm.GlobalObject

    let promiseProto = realm.NewObject()
    promiseProto.InternalTag = "Promise"

    // Promise constructor
    let promiseCtor = realm.NewFunction(name: "Promise") { r, _, args in
        guard !args.isEmpty, let execObj = args[0].ObjVal as? object.JSObject, execObj.Callable != nil else {
            return value.Value.Undefined
        }

        let pair = newPromise(realm: r, prototype: promiseProto)
        let p = pair.0
        let rec = pair.1

        let fns = createResolvingFunctions(realm: r, promiseObj: p, record: rec)
        let resFn = fns.0
        let rejFn = fns.1

        do {
            _ = try r.Call(execObj, args: [value.Value.Object(resFn), value.Value.Object(rejFn)])
        } catch {
            rejectPromise(realm: r, record: rec, reason: value.Value.String("\(error)"))
        }

        return value.Value.Object(p)
    }
    promiseCtor.Set("prototype", value.Value.Object(promiseProto))

    // Promise.prototype.then
    promiseProto.Set("then", value.Value.Object(realm.NewFunction(name: "then") { r, thisVal, args in
        guard let pObj = thisVal.ObjVal as? object.JSObject, let rec = pObj.NativeData as? PromiseRecord else {
            return value.Value.Undefined
        }

        var onFulfilled: object.JSObject? = nil
        if args.count > 0, let fObj = args[0].ObjVal as? object.JSObject, fObj.Callable != nil {
            onFulfilled = fObj
        }

        var onRejected: object.JSObject? = nil
        if args.count > 1, let rObj = args[1].ObjVal as? object.JSObject, rObj.Callable != nil {
            onRejected = rObj
        }

        let pair = newPromise(realm: r, prototype: promiseProto)
        let newP = pair.0
        let cap = PromiseCapability(promise: newP)

        if rec.state == 0 {
            // Pending
            rec.fulfillReactions.append(PromiseReaction(capability: cap, handler: onFulfilled, isReject: false))
            rec.rejectReactions.append(PromiseReaction(capability: cap, handler: onRejected, isReject: true))
        } else if rec.state == 1 {
            // Already fulfilled
            let currentVal = rec.result
            r.EnqueueJob {
                triggerPromiseReaction(realm: r, reaction: PromiseReaction(capability: cap, handler: onFulfilled, isReject: false), argument: currentVal, isReject: false)
            }
        } else if rec.state == 2 {
            // Already rejected
            let currentReason = rec.result
            r.EnqueueJob {
                triggerPromiseReaction(realm: r, reaction: PromiseReaction(capability: cap, handler: onRejected, isReject: true), argument: currentReason, isReject: true)
            }
        }

        return value.Value.Object(newP)
    }))

    // Promise.prototype.catch
    promiseProto.Set("catch", value.Value.Object(realm.NewFunction(name: "catch") { r, thisVal, args in
        guard let pObj = thisVal.ObjVal as? object.JSObject else { return value.Value.Undefined }
        if let thenProp = pObj.Get("then").ObjVal as? object.JSObject {
            let onRejected = args.isEmpty ? value.Value.Undefined : args[0]
            return try r.Call(thenProp, thisVal: thisVal, args: [value.Value.Undefined, onRejected])
        }
        return value.Value.Undefined
    }))

    // Promise.prototype.finally
    promiseProto.Set("finally", value.Value.Object(realm.NewFunction(name: "finally") { r, thisVal, args in
        guard let pObj = thisVal.ObjVal as? object.JSObject else { return value.Value.Undefined }
        if args.isEmpty || (args[0].ObjVal as? object.JSObject)?.Callable == nil {
            if let thenProp = pObj.Get("then").ObjVal as? object.JSObject {
                return try r.Call(thenProp, thisVal: thisVal, args: [])
            }
            return value.Value.Undefined
        }

        let callback = args[0].ObjVal as! object.JSObject
        let onFulfill = r.NewFunction(name: "finallyFulfill") { r, _, fArgs in
            let v = fArgs.isEmpty ? value.Value.Undefined : fArgs[0]
            _ = try r.Call(callback, args: [])
            return v
        }
        let onReject = r.NewFunction(name: "finallyReject") { r, _, rArgs in
            let reason = rArgs.isEmpty ? value.Value.Undefined : rArgs[0]
            _ = try r.Call(callback, args: [])
            let rejPair = newPromise(realm: r, prototype: promiseProto)
            rejectPromise(realm: r, record: rejPair.1, reason: reason)
            return value.Value.Object(rejPair.0)
        }

        if let thenProp = pObj.Get("then").ObjVal as? object.JSObject {
            return try r.Call(thenProp, thisVal: thisVal, args: [value.Value.Object(onFulfill), value.Value.Object(onReject)])
        }
        return value.Value.Undefined
    }))

    // Promise.resolve
    promiseCtor.Set("resolve", value.Value.Object(realm.NewFunction(name: "resolve") { r, _, args in
        let val = args.isEmpty ? value.Value.Undefined : args[0]
        if val.IsObject, let pObj = val.ObjVal as? object.JSObject, pObj.InternalTag == "Promise" {
            return val
        }
        let pair = newPromise(realm: r, prototype: promiseProto)
        let p = pair.0
        let rec = pair.1
        resolvePromise(realm: r, record: rec, promiseObj: p, resolution: val)
        return value.Value.Object(p)
    }))

    // Promise.reject
    promiseCtor.Set("reject", value.Value.Object(realm.NewFunction(name: "reject") { r, _, args in
        let reason = args.isEmpty ? value.Value.Undefined : args[0]
        let pair = newPromise(realm: r, prototype: promiseProto)
        let p = pair.0
        let rec = pair.1
        rejectPromise(realm: r, record: rec, reason: reason)
        return value.Value.Object(p)
    }))

    // Helper to extract array elements from args[0]
    func getIterableElements(_ arg: value.Value) -> [value.Value] {
        if arg.IsObject, let obj = arg.ObjVal as? object.JSObject {
            if obj.InternalTag == "Array" {
                return obj.Elements
            }
        }
        return []
    }

    // Promise.all
    promiseCtor.Set("all", value.Value.Object(realm.NewFunction(name: "all") { r, _, args in
        let pair = newPromise(realm: r, prototype: promiseProto)
        let allP = pair.0
        let allRec = pair.1

        if args.isEmpty {
            fulfillPromise(realm: r, record: allRec, val: value.Value.Object(r.NewArray()))
            return value.Value.Object(allP)
        }

        let elements = getIterableElements(args[0])
        if elements.isEmpty {
            fulfillPromise(realm: r, record: allRec, val: value.Value.Object(r.NewArray()))
            return value.Value.Object(allP)
        }

        let count = elements.count
        var remaining = count
        var results: [value.Value] = Array(repeating: value.Value.Undefined, count: count)
        let resultsArr = r.NewArray()

        for idx in 0..<count {
            let item = elements[idx]
            let itemPair = newPromise(realm: r, prototype: promiseProto)
            let itemP = itemPair.0
            let itemRec = itemPair.1
            resolvePromise(realm: r, record: itemRec, promiseObj: itemP, resolution: item)

            let onFulfill = r.NewFunction(name: "onFulfillAll") { r, _, fArgs in
                let val = fArgs.isEmpty ? value.Value.Undefined : fArgs[0]
                results[idx] = val
                remaining -= 1
                if remaining == 0 {
                    resultsArr.Elements = results
                    resultsArr.Set("length", value.Value.Int(int32(count)))
                    fulfillPromise(realm: r, record: allRec, val: value.Value.Object(resultsArr))
                }
                return value.Value.Undefined
            }

            let onReject = r.NewFunction(name: "onRejectAll") { r, _, rArgs in
                let reason = rArgs.isEmpty ? value.Value.Undefined : rArgs[0]
                rejectPromise(realm: r, record: allRec, reason: reason)
                return value.Value.Undefined
            }

            if let thenProp = itemP.Get("then").ObjVal as? object.JSObject {
                _ = try r.Call(thenProp, thisVal: value.Value.Object(itemP), args: [value.Value.Object(onFulfill), value.Value.Object(onReject)])
            }
        }

        return value.Value.Object(allP)
    }))

    // Promise.race
    promiseCtor.Set("race", value.Value.Object(realm.NewFunction(name: "race") { r, _, args in
        let pair = newPromise(realm: r, prototype: promiseProto)
        let raceP = pair.0
        let raceRec = pair.1

        if args.isEmpty {
            return value.Value.Object(raceP)
        }

        let elements = getIterableElements(args[0])
        for item in elements {
            let itemPair = newPromise(realm: r, prototype: promiseProto)
            let itemP = itemPair.0
            let itemRec = itemPair.1
            resolvePromise(realm: r, record: itemRec, promiseObj: itemP, resolution: item)

            let onFulfill = r.NewFunction(name: "onFulfillRace") { r, _, fArgs in
                let val = fArgs.isEmpty ? value.Value.Undefined : fArgs[0]
                fulfillPromise(realm: r, record: raceRec, val: val)
                return value.Value.Undefined
            }

            let onReject = r.NewFunction(name: "onRejectRace") { r, _, rArgs in
                let reason = rArgs.isEmpty ? value.Value.Undefined : rArgs[0]
                rejectPromise(realm: r, record: raceRec, reason: reason)
                return value.Value.Undefined
            }

            if let thenProp = itemP.Get("then").ObjVal as? object.JSObject {
                _ = try r.Call(thenProp, thisVal: value.Value.Object(itemP), args: [value.Value.Object(onFulfill), value.Value.Object(onReject)])
            }
        }

        return value.Value.Object(raceP)
    }))

    // Promise.allSettled
    promiseCtor.Set("allSettled", value.Value.Object(realm.NewFunction(name: "allSettled") { r, _, args in
        let pair = newPromise(realm: r, prototype: promiseProto)
        let settledP = pair.0
        let settledRec = pair.1

        if args.isEmpty {
            fulfillPromise(realm: r, record: settledRec, val: value.Value.Object(r.NewArray()))
            return value.Value.Object(settledP)
        }

        let elements = getIterableElements(args[0])
        if elements.isEmpty {
            fulfillPromise(realm: r, record: settledRec, val: value.Value.Object(r.NewArray()))
            return value.Value.Object(settledP)
        }

        let count = elements.count
        var remaining = count
        var results: [value.Value] = Array(repeating: value.Value.Undefined, count: count)
        let resultsArr = r.NewArray()

        for idx in 0..<count {
            let item = elements[idx]
            let itemPair = newPromise(realm: r, prototype: promiseProto)
            let itemP = itemPair.0
            let itemRec = itemPair.1
            resolvePromise(realm: r, record: itemRec, promiseObj: itemP, resolution: item)

            let onFulfill = r.NewFunction(name: "onFulfillSettled") { r, _, fArgs in
                let val = fArgs.isEmpty ? value.Value.Undefined : fArgs[0]
                let recordObj = r.NewObject()
                recordObj.Set("status", value.Value.String("fulfilled"))
                recordObj.Set("value", val)
                results[idx] = value.Value.Object(recordObj)

                remaining -= 1
                if remaining == 0 {
                    resultsArr.Elements = results
                    resultsArr.Set("length", value.Value.Int(int32(count)))
                    fulfillPromise(realm: r, record: settledRec, val: value.Value.Object(resultsArr))
                }
                return value.Value.Undefined
            }

            let onReject = r.NewFunction(name: "onRejectSettled") { r, _, rArgs in
                let reason = rArgs.isEmpty ? value.Value.Undefined : rArgs[0]
                let recordObj = r.NewObject()
                recordObj.Set("status", value.Value.String("rejected"))
                recordObj.Set("reason", reason)
                results[idx] = value.Value.Object(recordObj)

                remaining -= 1
                if remaining == 0 {
                    resultsArr.Elements = results
                    resultsArr.Set("length", value.Value.Int(int32(count)))
                    fulfillPromise(realm: r, record: settledRec, val: value.Value.Object(resultsArr))
                }
                return value.Value.Undefined
            }

            if let thenProp = itemP.Get("then").ObjVal as? object.JSObject {
                _ = try r.Call(thenProp, thisVal: value.Value.Object(itemP), args: [value.Value.Object(onFulfill), value.Value.Object(onReject)])
            }
        }

        return value.Value.Object(settledP)
    }))

    // Promise.any
    promiseCtor.Set("any", value.Value.Object(realm.NewFunction(name: "any") { r, _, args in
        let pair = newPromise(realm: r, prototype: promiseProto)
        let anyP = pair.0
        let anyRec = pair.1

        if args.isEmpty {
            rejectPromise(realm: r, record: anyRec, reason: value.Value.String("AggregateError: All promises were rejected"))
            return value.Value.Object(anyP)
        }

        let elements = getIterableElements(args[0])
        if elements.isEmpty {
            rejectPromise(realm: r, record: anyRec, reason: value.Value.String("AggregateError: All promises were rejected"))
            return value.Value.Object(anyP)
        }

        let count = elements.count
        var remaining = count
        var errors: [value.Value] = Array(repeating: value.Value.Undefined, count: count)

        for idx in 0..<count {
            let item = elements[idx]
            let itemPair = newPromise(realm: r, prototype: promiseProto)
            let itemP = itemPair.0
            let itemRec = itemPair.1
            resolvePromise(realm: r, record: itemRec, promiseObj: itemP, resolution: item)

            let onFulfill = r.NewFunction(name: "onFulfillAny") { r, _, fArgs in
                let val = fArgs.isEmpty ? value.Value.Undefined : fArgs[0]
                fulfillPromise(realm: r, record: anyRec, val: val)
                return value.Value.Undefined
            }

            let onReject = r.NewFunction(name: "onRejectAny") { r, _, rArgs in
                let reason = rArgs.isEmpty ? value.Value.Undefined : rArgs[0]
                errors[idx] = reason
                remaining -= 1
                if remaining == 0 {
                    rejectPromise(realm: r, record: anyRec, reason: value.Value.String("AggregateError: All promises were rejected"))
                }
                return value.Value.Undefined
            }

            if let thenProp = itemP.Get("then").ObjVal as? object.JSObject {
                _ = try r.Call(thenProp, thisVal: value.Value.Object(itemP), args: [value.Value.Object(onFulfill), value.Value.Object(onReject)])
            }
        }

        return value.Value.Object(anyP)
    }))

    // Promise.withResolvers (ECMA-262 §27.2.4.8)
    promiseCtor.Set("withResolvers", value.Value.Object(realm.NewFunction(name: "withResolvers") { r, _, _ in
        let pair = newPromise(realm: r, prototype: promiseProto)
        let promiseObj = pair.0
        let rec = pair.1

        let resolveFn = r.NewFunction(name: "resolve") { r, _, rArgs in
            let res = rArgs.isEmpty ? value.Value.Undefined : rArgs[0]
            resolvePromise(realm: r, record: rec, promiseObj: promiseObj, resolution: res)
            return value.Value.Undefined
        }

        let rejectFn = r.NewFunction(name: "reject") { r, _, rArgs in
            let reason = rArgs.isEmpty ? value.Value.Undefined : rArgs[0]
            rejectPromise(realm: r, record: rec, reason: reason)
            return value.Value.Undefined
        }

        let resObj = r.NewObject()
        resObj.Set("promise", value.Value.Object(promiseObj))
        resObj.Set("resolve", value.Value.Object(resolveFn))
        resObj.Set("reject", value.Value.Object(rejectFn))
        return value.Value.Object(resObj)
    }))

    // queueMicrotask
    let queueMicrotaskFn = realm.NewFunction(name: "queueMicrotask") { r, _, args in
        if !args.isEmpty, let fnObj = args[0].ObjVal as? object.JSObject, fnObj.Callable != nil {
            r.EnqueueJob {
                _ = try? r.Call(fnObj)
            }
        }
        return value.Value.Undefined
    }

    g.Set("Promise", value.Value.Object(promiseCtor))
    g.Set("queueMicrotask", value.Value.Object(queueMicrotaskFn))

    realm.Heap.Roots.AddRoot(promiseProto)
    realm.Heap.Roots.AddRoot(promiseCtor)
}
