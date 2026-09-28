package interp

import (
    "gc"
    "js/bytecode"
    "js/value"
    "js/object"
    "js/ic"
)

/// VMError represents a runtime JavaScript exception.
public enum VMError: Error, CustomStringConvertible {
    case error(string)

    public var Message: string {
        switch self {
        case .error(let msg): return msg
        }
    }

    public var description: string {
        return "Uncaught \(Message)"
    }
}

final class GeneratorRecord {
    let fn: bytecode.BytecodeFunction
    var pc: int = 0
    var savedStack: [value.Value] = []
    var thisValue: value.Value
    var isDone: bool = false

    init(fn: bytecode.BytecodeFunction, thisValue: value.Value, initialStack: [value.Value]) {
        self.fn = fn
        self.thisValue = thisValue
        self.savedStack = initialStack
    }
}

/// CallFrame records execution state for an active bytecode function invocation.
final class CallFrame {
    let fn: bytecode.BytecodeFunction
    var pc: int = 0
    let registerBase: int
    var thisValue: value.Value
    let feedback: ic.FeedbackVector
    var genRecord: GeneratorRecord? = nil

    init(fn: bytecode.BytecodeFunction, registerBase: int, thisValue: value.Value) {
        self.fn = fn
        self.registerBase = registerBase
        self.thisValue = thisValue
        self.feedback = ic.FeedbackVector(slotCount: fn.FeedbackSlotCount)
    }
}

/// VM executes JavaScript bytecode functions.
public final class VM {
    var stack: [value.Value] = []
    var acc: value.Value = value.Value.Undefined

    public init() {}

    /// CollectRoots returns all live cells held in VM registers and the accumulator.
    public func CollectRoots() -> [gc.Cell] {
        var roots: [gc.Cell] = []
        if acc.Type == .object, let c = acc.ObjVal as? gc.Cell {
            roots.append(c)
        }
        for val in stack {
            if val.Type == .object, let c = val.ObjVal as? gc.Cell {
                roots.append(c)
            }
        }
        return roots
    }

    /// Run executes a BytecodeFunction in the given Realm with thisValue and arguments.
    public func Run(_ fn: bytecode.BytecodeFunction, realm: object.Realm, thisValue: value.Value = value.Value.Undefined, args: [value.Value] = []) throws -> value.Value {
        let regBase = stack.count
        let totalRegisters = fn.RegisterCount + 2
        for _ in 0..<totalRegisters {
            stack.append(value.Value.Undefined)
        }

        // Store receiver 'this' at r0
        stack[regBase] = thisValue
        let regularParamCount = fn.HasRestParameter ? (fn.ParameterCount - 1) : fn.ParameterCount
        for i in 0..<regularParamCount {
            if i < args.count && regBase + 1 + i < stack.count {
                stack[regBase + 1 + i] = args[i]
            }
        }
        if fn.HasRestParameter {
            var restElements: [value.Value] = []
            if args.count > regularParamCount {
                for i in regularParamCount..<args.count {
                    restElements.append(args[i])
                }
            }
            let restArr = realm.NewArray(elements: restElements)
            let restSlot = regBase + 1 + regularParamCount
            if restSlot < stack.count {
                stack[restSlot] = value.Value.Object(restArr)
            }
        }

        if fn.IsGenerator {
            var initialStack: [value.Value] = []
            for i in regBase..<stack.count {
                initialStack.append(stack[i])
            }
            while stack.count > regBase { _ = stack.removeLast() }

            let rec = GeneratorRecord(fn: fn, thisValue: thisValue, initialStack: initialStack)
            let genObj = realm.NewObject()
            genObj.InternalTag = "Generator"

            genObj.Set("next", value.Value.Object(realm.NewFunction(name: "next") { r, _, _ in
                if rec.isDone {
                    let doneObj = r.NewObject()
                    doneObj.Set("value", value.Value.Undefined)
                    doneObj.Set("done", value.Value.Boolean(true))
                    return value.Value.Object(doneObj)
                }
                return try self.resumeGenerator(rec: rec, realm: r)
            }))

            genObj.Set("return", value.Value.Object(realm.NewFunction(name: "return") { r, _, retArgs in
                rec.isDone = true
                let retVal = retArgs.isEmpty ? value.Value.Undefined : retArgs[0]
                let doneObj = r.NewObject()
                doneObj.Set("value", retVal)
                doneObj.Set("done", value.Value.Boolean(true))
                return value.Value.Object(doneObj)
            }))

            return value.Value.Object(genObj)
        }

        if fn.IsAsync {
            let promiseCtor = realm.GlobalObject.Get("Promise")
            do {
                let frame = CallFrame(fn: fn, registerBase: regBase, thisValue: thisValue)
                let result = try dispatch(frame: frame, realm: realm)
                while stack.count > regBase { _ = stack.removeLast() }
                if promiseCtor.IsObject, let ctorObj = promiseCtor.ObjVal as? object.JSObject {
                    let resolveProp = ctorObj.Get("resolve")
                    if resolveProp.IsObject, let resFn = resolveProp.ObjVal as? object.JSObject {
                        return try realm.Call(resFn, thisVal: promiseCtor, args: [result])
                    }
                }
                return result
            } catch {
                while stack.count > regBase { _ = stack.removeLast() }
                if promiseCtor.IsObject, let ctorObj = promiseCtor.ObjVal as? object.JSObject {
                    let rejectProp = ctorObj.Get("reject")
                    if rejectProp.IsObject, let rejFn = rejectProp.ObjVal as? object.JSObject {
                        let errMsg = value.Value.String("\(error)")
                        return try realm.Call(rejFn, thisVal: promiseCtor, args: [errMsg])
                    }
                }
                throw error
            }
        }

        let frame = CallFrame(fn: fn, registerBase: regBase, thisValue: thisValue)
        let result = try dispatch(frame: frame, realm: realm)

        // Unwind stack
        while stack.count > regBase {
            _ = stack.removeLast()
        }
        return result
    }

    func resumeGenerator(rec: GeneratorRecord, realm: object.Realm) throws -> value.Value {
        let regBase = stack.count
        for val in rec.savedStack {
            stack.append(val)
        }
        let frame = CallFrame(fn: rec.fn, registerBase: regBase, thisValue: rec.thisValue)
        frame.pc = rec.pc
        frame.genRecord = rec
        let res = try dispatch(frame: frame, realm: realm)
        while stack.count > regBase { _ = stack.removeLast() }
        return res
    }

    func dispatch(frame: CallFrame, realm: object.Realm) throws -> value.Value {
        let instrs = frame.fn.Instructions
        let constants = frame.fn.Constants
        let rBase = frame.registerBase

        while frame.pc < instrs.count {
            let instr = instrs[frame.pc]
            frame.pc += 1

            switch instr.Op {
            case .ldaUndefined:
                acc = value.Value.Undefined

            case .ldaNull:
                acc = value.Value.Null

            case .ldaTrue:
                acc = value.Value.True

            case .ldaFalse:
                acc = value.Value.False

            case .ldaZero:
                acc = value.Value.Int(0)

            case .ldaInt32:
                acc = value.Value.Int(instr.Imm)

            case .ldaConstant:
                let idx = Int(instr.Imm)
                if idx < constants.count {
                    switch constants[idx] {
                    case .stringVal(let s):
                        acc = value.Value.String(s)
                    case .numberVal(let n):
                        acc = value.Value.Number(n)
                    case .boolVal(let b):
                        acc = value.Value.Boolean(b)
                    case .fnVal(let code):
                        let jsFn = realm.NewBytecodeFunction(code)
                        acc = value.Value.Object(jsFn)
                    }
                }

            case .ldar:
                let rIdx = rBase + Int(instr.R0)
                if rIdx < stack.count {
                    acc = stack[rIdx]
                }

            case .star:
                let rIdx = rBase + Int(instr.R0)
                while stack.count <= rIdx {
                    stack.append(value.Value.Undefined)
                }
                stack[rIdx] = acc

            case .mov:
                let srcIdx = rBase + Int(instr.R0)
                let dstIdx = rBase + Int(instr.R1)
                while stack.count <= dstIdx {
                    stack.append(value.Value.Undefined)
                }
                stack[dstIdx] = (srcIdx < stack.count) ? stack[srcIdx] : value.Value.Undefined

            case .ldaGlobal:
                let idx = Int(instr.Imm)
                if idx < constants.count, case .stringVal(let name) = constants[idx] {
                    acc = realm.GlobalObject.Get(name)
                }

            case .staGlobal:
                let idx = Int(instr.Imm)
                if idx < constants.count, case .stringVal(let name) = constants[idx] {
                    realm.GlobalObject.Set(name, acc)
                }

            case .ldaNamedProperty:
                let rIdx = rBase + Int(instr.R0)
                let objVal = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                let idx = Int(instr.Imm)
                if let obj = objVal.ObjVal as? object.JSObject, idx < constants.count, case .stringVal(let prop) = constants[idx] {
                    acc = obj.Get(prop)
                } else if objVal.IsString, idx < constants.count, case .stringVal(let prop) = constants[idx] {
                    if prop == "length" {
                        acc = value.Value.Int(int32(objVal.StrVal.count))
                    } else {
                        acc = value.Value.Undefined
                    }
                } else {
                    acc = value.Value.Undefined
                }

            case .staNamedProperty:
                let rIdx = rBase + Int(instr.R0)
                let objVal = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                let idx = Int(instr.Imm)
                if let obj = objVal.ObjVal as? object.JSObject, idx < constants.count, case .stringVal(let prop) = constants[idx] {
                    obj.Set(prop, acc)
                }

            case .ldaKeyedProperty:
                let rIdx = rBase + Int(instr.R0)
                let objVal = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                if let obj = objVal.ObjVal as? object.JSObject {
                    if acc.IsNumber {
                        acc = obj.GetElement(Int(acc.ToInt32()))
                    } else {
                        acc = obj.Get(acc.ToString())
                    }
                } else {
                    acc = value.Value.Undefined
                }

            case .staKeyedProperty:
                let rIdx = rBase + Int(instr.R0)
                let kIdx = rBase + Int(instr.R1)
                let objVal = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                let keyVal = (kIdx < stack.count) ? stack[kIdx] : value.Value.Undefined
                if let obj = objVal.ObjVal as? object.JSObject {
                    if keyVal.IsNumber {
                        obj.SetElement(Int(keyVal.ToInt32()), acc)
                    } else {
                        obj.Set(keyVal.ToString(), acc)
                    }
                }

            case .ldaContextSlot, .staContextSlot:
                // Context slot placeholder
                break

            case .add:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                if left.IsString || acc.IsString {
                    acc = value.Value.String(left.ToString() + acc.ToString())
                } else if left.Type == .int32 && acc.Type == .int32 {
                    let sum = int64(left.IntVal) + int64(acc.IntVal)
                    if sum >= int64(int32.min) && sum <= int64(int32.max) {
                        acc = value.Value.Int(int32(sum))
                    } else {
                        acc = value.Value.Number(float64(sum))
                    }
                } else {
                    acc = value.Value.Number(left.ToNumber() + acc.ToNumber())
                }

            case .sub:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                if left.Type == .int32 && acc.Type == .int32 {
                    acc = value.Value.Int(left.IntVal - acc.IntVal)
                } else {
                    acc = value.Value.Number(left.ToNumber() - acc.ToNumber())
                }

            case .mul:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                if left.Type == .int32 && acc.Type == .int32 {
                    acc = value.Value.Int(left.IntVal * acc.IntVal)
                } else {
                    acc = value.Value.Number(left.ToNumber() * acc.ToNumber())
                }

            case .div:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                let denom = acc.ToNumber()
                if denom == 0.0 {
                    acc = value.Value.Number(left.ToNumber() >= 0 ? float64.infinity : -float64.infinity)
                } else {
                    acc = value.Value.Number(left.ToNumber() / denom)
                }

            case .mod:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                if left.Type == .int32 && acc.Type == .int32 && acc.IntVal != 0 {
                    acc = value.Value.Int(left.IntVal % acc.IntVal)
                } else {
                    acc = value.Value.Number(left.ToNumber().truncatingRemainder(dividingBy: acc.ToNumber()))
                }

            case .exp:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                let baseVal = left.ToNumber()
                let expVal = acc.ToNumber()
                acc = value.Value.Number(power(baseVal, expVal))

            case .bitAnd:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                acc = value.Value.Int(left.ToInt32() & acc.ToInt32())

            case .bitOr:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                acc = value.Value.Int(left.ToInt32() | acc.ToInt32())

            case .bitXor:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                acc = value.Value.Int(left.ToInt32() ^ acc.ToInt32())

            case .shiftLeft:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                let shiftCount = Int(acc.ToUint32() & 0x1F)
                let lval = Int(left.ToInt32())
                let res = lval << shiftCount
                acc = value.Value.Int(int32(res))

            case .shiftRight:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                let shiftCount = Int(acc.ToUint32() & 0x1F)
                let lval = Int(left.ToInt32())
                let res = lval >> shiftCount
                acc = value.Value.Int(int32(res))

            case .shiftRightLogical:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                let shiftCount = Int(acc.ToUint32() & 0x1F)
                let lval = Int(left.ToInt32())
                if shiftCount == 0 {
                    let d = lval >= 0 ? float64(lval) : float64(lval) + 4294967296.0
                    acc = value.Value.Number(d)
                } else if lval >= 0 {
                    let res = lval >> shiftCount
                    acc = value.Value.Number(float64(res))
                } else {
                    let half = (lval >> 1) & 0x7FFFFFFF
                    let res = half >> (shiftCount - 1)
                    acc = value.Value.Number(float64(res))
                }

            case .negate:
                if acc.Type == .int32 {
                    acc = value.Value.Int(-acc.IntVal)
                } else {
                    acc = value.Value.Number(-acc.ToNumber())
                }

            case .bitwiseNot:
                acc = value.Value.Int(~acc.ToInt32())

            case .toBooleanLogicalNot:
                acc = value.Value.Boolean(!acc.ToBoolean())

            case .typeOf:
                switch acc.Type {
                case .undefined: acc = value.Value.String("undefined")
                case .null: acc = value.Value.String("object")
                case .boolean: acc = value.Value.String("boolean")
                case .int32, .number: acc = value.Value.String("number")
                case .string: acc = value.Value.String("string")
                case .symbol: acc = value.Value.String("symbol")
                case .object:
                    if let obj = acc.ObjVal as? object.JSObject, obj.Callable != nil {
                        acc = value.Value.String("function")
                    } else {
                        acc = value.Value.String("object")
                    }
                }

            case .testEqual:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                acc = value.Value.Boolean(value.AbstractEquals(left, acc))

            case .testStrictEqual:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                acc = value.Value.Boolean(value.StrictEquals(left, acc))

            case .testNotEqual:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                acc = value.Value.Boolean(!value.AbstractEquals(left, acc))

            case .testStrictNotEqual:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                acc = value.Value.Boolean(!value.StrictEquals(left, acc))

            case .testLessThan:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                if left.IsString && acc.IsString {
                    acc = value.Value.Boolean(left.StrVal < acc.StrVal)
                } else {
                    acc = value.Value.Boolean(left.ToNumber() < acc.ToNumber())
                }

            case .testGreaterThan:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                if left.IsString && acc.IsString {
                    acc = value.Value.Boolean(left.StrVal > acc.StrVal)
                } else {
                    acc = value.Value.Boolean(left.ToNumber() > acc.ToNumber())
                }

            case .testLessThanOrEqual:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                if left.IsString && acc.IsString {
                    acc = value.Value.Boolean(left.StrVal <= acc.StrVal)
                } else {
                    acc = value.Value.Boolean(left.ToNumber() <= acc.ToNumber())
                }

            case .testGreaterThanOrEqual:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                if left.IsString && acc.IsString {
                    acc = value.Value.Boolean(left.StrVal >= acc.StrVal)
                } else {
                    acc = value.Value.Boolean(left.ToNumber() >= acc.ToNumber())
                }

            case .testIn:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                if let obj = acc.ObjVal as? object.JSObject {
                    acc = value.Value.Boolean(obj.Has(left.ToString()))
                } else {
                    throw VMError.error("TypeError: Cannot use 'in' operator to search in primitive")
                }

            case .testInstanceOf:
                let rIdx = rBase + Int(instr.R0)
                let left = (rIdx < stack.count) ? stack[rIdx] : value.Value.Undefined
                var result = false
                if left.IsObject, let ctorObj = acc.ObjVal as? object.JSObject {
                    let targetProto = ctorObj.Get("prototype")
                    if targetProto.IsObject, let protoObj = targetProto.ObjVal as? object.JSObject {
                        var cur = (left.ObjVal as? object.JSObject)?.Prototype
                        while let p = cur {
                            if p === protoObj {
                                result = true
                                break
                            }
                            cur = p.Prototype
                        }
                    }
                }
                acc = value.Value.Boolean(result)

            case .jump:
                frame.pc = (frame.pc - 1) + Int(instr.Offset)

            case .jumpIfTrue:
                if acc.ToBoolean() {
                    frame.pc = (frame.pc - 1) + Int(instr.Offset)
                }

            case .jumpIfFalse:
                if !acc.ToBoolean() {
                    frame.pc = (frame.pc - 1) + Int(instr.Offset)
                }

            case .jumpIfNull:
                if acc.IsNull {
                    frame.pc = (frame.pc - 1) + Int(instr.Offset)
                }

            case .jumpIfUndefined:
                if acc.IsUndefined {
                    frame.pc = (frame.pc - 1) + Int(instr.Offset)
                }

            case .jumpIfNotUndefined:
                if !acc.IsUndefined {
                    frame.pc = (frame.pc - 1) + Int(instr.Offset)
                }

            case .call:
                let calleeIdx = rBase + Int(instr.R0)
                let recvIdx = rBase + Int(instr.R1)
                let calleeVal = (calleeIdx < stack.count) ? stack[calleeIdx] : value.Value.Undefined
                let recvVal = (recvIdx < stack.count) ? stack[recvIdx] : value.Value.Undefined
                let argCount = Int(instr.Imm)
                var callArgs: [value.Value] = []
                for i in 0..<argCount {
                    let aIdx = rBase + Int(instr.R2) + i
                    callArgs.append((aIdx < stack.count) ? stack[aIdx] : value.Value.Undefined)
                }
                if let obj = calleeVal.ObjVal as? object.JSObject, let callable = obj.Callable {
                    switch callable {
                    case .native(let cb):
                        acc = try cb(realm, recvVal, callArgs)
                    case .bytecode(let code):
                        acc = try Run(code, realm: realm, thisValue: recvVal, args: callArgs)
                    }
                } else {
                    throw VMError.error("TypeError: \(calleeVal) is not a function")
                }

            case .callProperty:
                acc = value.Value.Undefined

            case .construct:
                let calleeIdx = rBase + Int(instr.R0)
                let calleeVal = (calleeIdx < stack.count) ? stack[calleeIdx] : value.Value.Undefined
                let argCount = Int(instr.Imm)
                var callArgs: [value.Value] = []
                for a in 0..<argCount {
                    let aIdx = rBase + Int(instr.R2) + a
                    if aIdx < stack.count {
                        callArgs.append(stack[aIdx])
                    }
                }
                if let obj = calleeVal.ObjVal as? object.JSObject, let callable = obj.Callable {
                    switch callable {
                    case .native(let cb):
                        acc = try cb(realm, value.Value.Undefined, callArgs)
                    case .bytecode(let code):
                        let instance = realm.NewObject()
                        if let proto = obj.Get("prototype").ObjVal as? object.JSObject {
                            instance.Prototype = proto
                        }
                        let res = try Run(code, realm: realm, thisValue: value.Value.Object(instance), args: callArgs)
                        acc = (res.Type == .object && res.ObjVal != nil) ? res : value.Value.Object(instance)
                    }
                } else {
                    throw VMError.error("TypeError: \(calleeVal) is not a constructor")
                }

            case .returnOp:
                if let rec = frame.genRecord {
                    rec.isDone = true
                    let resObj = realm.NewObject()
                    resObj.Set("value", acc)
                    resObj.Set("done", value.Value.Boolean(true))
                    return value.Value.Object(resObj)
                }
                return acc

            case .throwOp:
                throw VMError.error(acc.ToString())

            case .awaitOp:
                if acc.IsObject, let obj = acc.ObjVal as? object.JSObject {
                    let thenProp = obj.Get("then")
                    if thenProp.IsObject, let thenFn = thenProp.ObjVal as? object.JSObject, thenFn.Callable != nil {
                        var settled = false
                        var fulfilledVal = value.Value.Undefined
                        var rejectedErr: value.Value? = nil

                        let onFulfill = realm.NewFunction(name: "awaitFulfill") { _, _, args in
                            settled = true
                            fulfilledVal = args.isEmpty ? value.Value.Undefined : args[0]
                            return value.Value.Undefined
                        }
                        let onReject = realm.NewFunction(name: "awaitReject") { _, _, args in
                            settled = true
                            rejectedErr = args.isEmpty ? value.Value.Undefined : args[0]
                            return value.Value.Undefined
                        }

                        _ = try realm.Call(thenFn, thisVal: acc, args: [value.Value.Object(onFulfill), value.Value.Object(onReject)])
                        realm.RunJobs()

                        if let err = rejectedErr {
                            throw VMError.error(err.ToString())
                        }
                        if settled {
                            acc = fulfilledVal
                        }
                    }
                }

            case .yieldOp:
                if let rec = frame.genRecord {
                    rec.pc = frame.pc
                    rec.savedStack = []
                    for i in rBase..<stack.count {
                        rec.savedStack.append(stack[i])
                    }
                    let resObj = realm.NewObject()
                    resObj.Set("value", acc)
                    resObj.Set("done", value.Value.Boolean(false))
                    return value.Value.Object(resObj)
                }

            case .createObjectLiteral:
                let obj = realm.NewObject()
                acc = value.Value.Object(obj)

            case .createArrayLiteral:
                let arr = realm.NewArray()
                acc = value.Value.Object(arr)

            case .createClosure:
                let idx = Int(instr.Imm)
                if idx < constants.count, case .fnVal(let code) = constants[idx] {
                    let jsFn = realm.NewBytecodeFunction(code)
                    acc = value.Value.Object(jsFn)
                }

            case .setProto:
                let rIdx = rBase + Int(instr.R0)
                if rIdx < stack.count, let target = stack[rIdx].ObjVal as? object.JSObject {
                    if acc.IsNull {
                        target.Prototype = nil
                    } else if let proto = acc.ObjVal as? object.JSObject {
                        target.Prototype = proto
                    }
                }

            case .callWithSpread:
                let calleeIdx = rBase + Int(instr.R0)
                let recvIdx = rBase + Int(instr.R1)
                let argsArrIdx = rBase + Int(instr.R2)
                let calleeVal = (calleeIdx < stack.count) ? stack[calleeIdx] : value.Value.Undefined
                let recvVal = (recvIdx < stack.count) ? stack[recvIdx] : value.Value.Undefined
                var callArgs: [value.Value] = []
                if argsArrIdx < stack.count, let arrObj = stack[argsArrIdx].ObjVal as? object.JSObject {
                    callArgs = arrObj.Elements
                }
                if let obj = calleeVal.ObjVal as? object.JSObject, let callable = obj.Callable {
                    switch callable {
                    case .native(let cb):
                        acc = try cb(realm, recvVal, callArgs)
                    case .bytecode(let code):
                        acc = try Run(code, realm: realm, thisValue: recvVal, args: callArgs)
                    }
                } else {
                    throw VMError.error("TypeError: \(calleeVal) is not a function")
                }

            case .appendArrayElement:
                let rIdx = rBase + Int(instr.R0)
                if rIdx < stack.count, let arr = stack[rIdx].ObjVal as? object.JSObject {
                    arr.SetElement(arr.Elements.count, acc)
                }

            case .spreadIntoArray:
                let rIdx = rBase + Int(instr.R0)
                if rIdx < stack.count, let dest = stack[rIdx].ObjVal as? object.JSObject {
                    if let src = acc.ObjVal as? object.JSObject {
                        for el in src.Elements {
                            dest.SetElement(dest.Elements.count, el)
                        }
                    }
                }

            case .spreadIntoObject:
                let rIdx = rBase + Int(instr.R0)
                if rIdx < stack.count, let dest = stack[rIdx].ObjVal as? object.JSObject {
                    if let src = acc.ObjVal as? object.JSObject {
                        for k in src.Keys {
                            dest.Set(k, src.Get(k))
                        }
                    }
                }

            case .sliceArrayFrom:
                let rIdx = rBase + Int(instr.R0)
                let start = Int(instr.Imm)
                var restElements: [value.Value] = []
                if rIdx < stack.count, let src = stack[rIdx].ObjVal as? object.JSObject {
                    let elCount = src.Elements.count
                    if start < elCount {
                        for i in start..<elCount {
                            restElements.append(src.Elements[i])
                        }
                    }
                }
                acc = value.Value.Object(realm.NewArray(elements: restElements))

            case .deleteNamedProperty:
                let rIdx = rBase + Int(instr.R0)
                let idx = Int(instr.Imm)
                if rIdx < stack.count, let obj = stack[rIdx].ObjVal as? object.JSObject, idx < constants.count, case .stringVal(let prop) = constants[idx] {
                    _ = obj.Delete(prop)
                }
            }
        }

        if let rec = frame.genRecord {
            rec.isDone = true
            let resObj = realm.NewObject()
            resObj.Set("value", acc)
            resObj.Set("done", value.Value.Boolean(true))
            return value.Value.Object(resObj)
        }
        return acc
    }

    func power(_ base: float64, _ exp: float64) -> float64 {
        if exp == 0.0 { return 1.0 }
        if exp == 1.0 { return base }
        if exp == 2.0 { return base * base }
        var result = 1.0
        var b = base
        var e = int64(exp)
        if float64(e) == exp && e > 0 {
            while e > 0 {
                if (e & 1) == 1 { result *= b }
                b *= b
                e >>= 1
            }
            return result
        }
        return base // fallback
    }
}
