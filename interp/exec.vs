package interp

import (
    "js/bytecode"
    "js/object"
    "js/str"
    "js/value"
)

extension Engine {
    /// exec is the dispatch loop.
    func exec(_ f: Frame) throws -> Exit {
        let code = f.t.Code
        let consts = f.t.Constants
        let strict = f.t.Strict
        var pc = f.pc
        var acc = f.acc
        while true {
            let ins = code[pc]
            f.pc = pc
            pc += 1
            switch ins.Op {
            case .nop, .debugger:
                break
            case .ldaUndefined:
                acc = .undefined
            case .ldaNull:
                acc = .null
            case .ldaTrue:
                acc = .bool(true)
            case .ldaFalse:
                acc = .bool(false)
            case .ldaEmpty:
                acc = .empty
            case .ldaSmi:
                acc = .number(float64(ins.A))
            case .ldaConst:
                acc = constValue(consts[int(ins.A)])
            case .ldar:
                acc = f.regs[int(ins.A)]
            case .star:
                f.regs[int(ins.A)] = acc
            case .mov:
                f.regs[int(ins.B)] = f.regs[int(ins.A)]

            // The frame.
            case .ldaArg:
                let i = int(ins.A)
                acc = i < f.args.count ? f.args[i] : .undefined
            case .createRest:
                let from = int(ins.A)
                var rest: [Value] = []
                var i = from
                while i < f.args.count { rest.append(f.args[i]); i += 1 }
                acc = .object(object.CreateArrayFromList(f.realm, rest))
            case .createArguments:
                acc = .object(makeArguments(f, mapped: ins.A == 1))
            case .ldaThis:
                acc = try thisOf(f)
            case .ldaNewTarget:
                if let fe = f.funcEnv { acc = fe.NewTarget } else { acc = f.newTarget }
            case .ldaCallee:
                if let fn = f.fn { acc = .object(fn) } else { acc = .undefined }
            case .ldaHomeObject:
                if let fn = activeFunction(f), let h = fn.HomeObject { acc = .object(h) } else { acc = .undefined }

            // Contexts.
            case .pushContext:
                if ins.A < 0 {
                    // A with statement's object environment.
                    let o = try object.ToObject(acc)
                    let c = object.Context(slots: 0, parent: f.ctx, info: nil)
                    c.WithObject = o
                    f.ctx = c
                } else {
                    let info: bytecode.ScopeInfo? = ins.B >= 0 ? f.t.Scopes[int(ins.B)] : nil
                    f.ctx = object.Context(slots: int(ins.A), parent: f.ctx, info: info)
                }
                f.ctxDepth += 1
            case .popContext:
                f.ctx = f.ctx?.Parent
                f.ctxDepth -= 1
            case .cloneContext:
                if let c = f.ctx { f.ctx = object.Context(copying: c) }
            case .ldaCtx:
                acc = contextAt(f, ins.A).Slots[int(ins.B)]
            case .ldaCtxChecked:
                acc = contextAt(f, ins.A).Slots[int(ins.B)]
                if acc.IsEmpty { throw tdz(consts[int(ins.C)]) }
            case .staCtx:
                contextAt(f, ins.A).Slots[int(ins.B)] = acc
            case .checkHole:
                if f.regs[int(ins.A)].IsEmpty { throw tdz(consts[int(ins.B)]) }
            case .checkHoleCtx:
                if contextAt(f, ins.A).Slots[int(ins.B)].IsEmpty { throw tdz(consts[int(ins.C)]) }
            case .throwIfHole:
                if acc.IsEmpty { throw tdz(consts[int(ins.A)]) }
            case .throwConstAssign:
                throw object.ThrowTypeError("Assignment to constant variable.")

            // Globals and dynamic names.
            case .ldaGlobal:
                acc = try loadGlobal(f.realm, constString(consts[int(ins.A)]), typeofOperand: false)
            case .ldaGlobalTypeof:
                acc = try loadGlobal(f.realm, constString(consts[int(ins.A)]), typeofOperand: true)
            case .staGlobal:
                try storeGlobal(f.realm, constString(consts[int(ins.A)]), acc, strict: ins.B == 1)
            case .initGlobalLexical:
                let name = constString(consts[int(ins.A)])
                if let b = f.realm.GlobalLexicals[name] {
                    b.Value = acc
                }
            case .declareGlobals:
                if case .globals(let g) = consts[int(ins.A)] {
                    try declareGlobals(f, g)
                }
            case .ldaLookup:
                acc = try lookupName(f, constString(consts[int(ins.A)]), typeofOperand: false)
            case .ldaLookupTypeof:
                acc = try lookupName(f, constString(consts[int(ins.A)]), typeofOperand: true)
            case .ldaLookupThis:
                let (v, thisV) = try lookupNameWithThis(f, constString(consts[int(ins.A)]))
                acc = v
                f.regs[int(ins.B)] = thisV
            case .staLookup:
                try storeName(f, constString(consts[int(ins.A)]), acc, strict: ins.B == 1)
            case .deleteLookup:
                acc = .bool(try deleteName(f, constString(consts[int(ins.A)])))
            case .declareEvalVar:
                try declareEvalVar(f, constString(consts[int(ins.A)]), acc, assign: false)
            case .declareEvalFunction:
                try declareEvalVar(f, constString(consts[int(ins.A)]), acc, assign: true)

            // Properties.
            case .getNamed:
                let base = f.regs[int(ins.A)]
                let key = constKey(consts[int(ins.B)])
                if case .object(let o) = base {
                    acc = try o.Get(key, base)
                } else {
                    acc = try object.GetV(base, key)
                }
            case .getKeyed:
                let base = f.regs[int(ins.A)]
                if case .object(let o) = base {
                    if let arr = o as? object.ArrayObject, case .number(let d) = acc, d >= 0, d < 4294967295, d == d.rounded(.towardZero), !arr.Sparse {
                        let i = int(d)
                        if i < arr.Dense.count, !arr.Dense[i].IsEmpty {
                            acc = arr.Dense[i]
                            break
                        }
                    }
                    acc = try o.Get(try object.ToPropertyKey(acc), base)
                } else {
                    if base.IsNullish {
                        let k = try object.ToPropertyKey(acc)
                        throw object.ThrowTypeError("Cannot read properties of \(base.IsNull ? "null" : "undefined") (reading '\(object.KeyDisplay(k))')")
                    }
                    acc = try object.GetV(base, try object.ToPropertyKey(acc))
                }
            case .setNamed:
                try object.PutProperty(f.regs[int(ins.A)], constKey(consts[int(ins.B)]), acc, strict: ins.C == 1)
            case .setKeyed:
                let base = f.regs[int(ins.A)]
                let kv = f.regs[int(ins.B)]
                if case .object(let o) = base, let arr = o as? object.ArrayObject, case .number(let d) = kv, d >= 0, d < 4294967295, d == d.rounded(.towardZero) {
                    if try arr.Set(value.PropertyKey.index(uint32(d)), acc, base) { break }
                    if ins.C == 1 { throw object.ThrowTypeError("Cannot assign to read only property '\(int64(d))' of object") }
                    break
                }
                if base.IsNullish {
                    let k = try object.ToPropertyKey(kv)
                    throw object.ThrowTypeError("Cannot set properties of \(base.IsNull ? "null" : "undefined") (setting '\(object.KeyDisplay(k))')")
                }
                try object.PutProperty(base, try object.ToPropertyKey(kv), acc, strict: ins.C == 1)
            case .defineNamed:
                if case .object(let o) = f.regs[int(ins.A)] {
                    try object.CreateDataPropertyOrThrow(o, constKey(consts[int(ins.B)]), acc)
                }
            case .defineKeyed:
                if case .object(let o) = f.regs[int(ins.A)] {
                    let k = try object.ToPropertyKey(f.regs[int(ins.B)])
                    if k.IsPrivate {
                        o.store(k, object.Slot(value: acc, flags: 1))
                    } else {
                        try object.CreateDataPropertyOrThrow(o, k, acc)
                    }
                }
            case .defineGetter, .defineSetter:
                if case .object(let o) = f.regs[int(ins.A)], case .object(let fn) = acc {
                    let k = try object.ToPropertyKey(f.regs[int(ins.B)])
                    if let jf = fn as? object.JSFunction { jf.HomeObject = o }
                    object.SetFunctionName(fn, k, prefix: ins.Op == .defineGetter ? "get" : "set")
                    var d = object.PropertyDescriptor()
                    if ins.Op == .defineGetter { d.Get = acc } else { d.Set = acc }
                    d.Enumerable = ins.C == 1
                    d.Configurable = true
                    try object.DefinePropertyOrThrow(o, k, d)
                }
            case .defineMethod:
                if case .object(let o) = f.regs[int(ins.A)], case .object(let fn) = acc {
                    let k = try object.ToPropertyKey(f.regs[int(ins.B)])
                    if let jf = fn as? object.JSFunction { jf.HomeObject = o }
                    object.SetFunctionName(fn, k)
                    try object.DefinePropertyOrThrow(o, k, object.PropertyDescriptor.Data(acc, writable: true, enumerable: ins.C == 1, configurable: true))
                }
            case .setFunctionName:
                if case .object(let fn) = acc {
                    let k = try object.ToPropertyKey(f.regs[int(ins.A)])
                    object.SetFunctionName(fn, k, prefix: ins.B == 1 ? "get" : (ins.B == 2 ? "set" : ""))
                }
            case .setProto:
                if case .object(let o) = f.regs[int(ins.A)] {
                    if case .object(let p) = acc { _ = o.OrdinarySetPrototypeOf(p) } else if acc.IsNull { _ = o.OrdinarySetPrototypeOf(nil) }
                }
            case .setHomeObject:
                if case .object(let fn) = acc, let jf = fn as? object.JSFunction, case .object(let h) = f.regs[int(ins.A)] {
                    jf.HomeObject = h
                }
            case .deleteProperty:
                let o = try object.ToObject(f.regs[int(ins.A)])
                let k = try object.ToPropertyKey(acc)
                let ok = try o.Delete(k)
                if !ok && ins.B == 1 {
                    throw object.ThrowTypeError("Cannot delete property '\(object.KeyDisplay(k))' of \(object.Describe(.object(o)))")
                }
                acc = .bool(ok)
            case .getSuper:
                let k = try object.ToPropertyKey(f.regs[int(ins.A)])
                let base = try superBase(f)
                acc = try base.Get(k, try thisOf(f))
            case .setSuper:
                let k = try object.ToPropertyKey(f.regs[int(ins.A)])
                let base = try superBase(f)
                let ok = try base.Set(k, acc, try thisOf(f))
                if !ok && strict {
                    throw object.ThrowTypeError("Cannot assign to read only property '\(object.KeyDisplay(k))' of object")
                }
            case .getPrivate:
                acc = try privateGet(f.regs[int(ins.A)], f.regs[int(ins.B)])
            case .setPrivate:
                try privateSet(f.regs[int(ins.A)], f.regs[int(ins.B)], acc)
            case .definePrivate:
                guard case .object(let o) = f.regs[int(ins.A)], case .symbol(let s) = f.regs[int(ins.B)] else { break }
                if o.PrivateFind(s) >= 0 {
                    throw object.ThrowTypeError("Cannot initialize \(s.DescriptiveString) twice on the same object")
                }
                o.store(.symbol(s), object.Slot(value: acc, flags: 1))
            case .privateIn:
                guard case .object(let o) = acc else {
                    throw object.ThrowTypeError("Cannot use 'in' operator to search for '\(nameOfPrivate(f.regs[int(ins.A)]))' in \(object.Describe(acc))")
                }
                if case .symbol(let s) = f.regs[int(ins.A)] {
                    acc = .bool(o.PrivateFind(s) >= 0)
                } else {
                    acc = .bool(false)
                }
            case .copyDataProperties:
                if case .object(let target) = f.regs[int(ins.A)] {
                    var excluded: [value.PropertyKey] = []
                    if ins.B >= 0, case .object(let ex) = f.regs[int(ins.B)], let arr = ex as? object.ArrayObject {
                        for v in arr.Dense { excluded.append(try object.ToPropertyKey(v)) }
                    }
                    try object.CopyDataProperties(target, acc, excluded: excluded)
                }
            case .toPropertyKey:
                acc = object.KeyToValue(try object.ToPropertyKey(acc))
            case .requireObjectCoercible:
                if acc.IsNullish {
                    throw object.ThrowTypeError("Cannot destructure '\(object.Describe(acc))' as it is \(acc.IsNull ? "null" : "undefined").")
                }

            // Binary operators: acc = r[A] op acc.
            case .add:
                let l = f.regs[int(ins.A)]
                if case .number(let a) = l, case .number(let b) = acc {
                    acc = .number(a + b)
                } else {
                    acc = try object.Add(l, acc)
                }
            case .sub:
                acc = try arith(.sub, f.regs[int(ins.A)], acc)
            case .mul:
                acc = try arith(.mul, f.regs[int(ins.A)], acc)
            case .div:
                acc = try arith(.div, f.regs[int(ins.A)], acc)
            case .mod:
                acc = try arith(.mod, f.regs[int(ins.A)], acc)
            case .exp:
                acc = try arith(.exp, f.regs[int(ins.A)], acc)
            case .bitAnd:
                acc = try arith(.and, f.regs[int(ins.A)], acc)
            case .bitOr:
                acc = try arith(.or, f.regs[int(ins.A)], acc)
            case .bitXor:
                acc = try arith(.xor, f.regs[int(ins.A)], acc)
            case .shl:
                acc = try arith(.shl, f.regs[int(ins.A)], acc)
            case .sar:
                acc = try arith(.sar, f.regs[int(ins.A)], acc)
            case .shr:
                acc = try arith(.shr, f.regs[int(ins.A)], acc)
            case .testEq:
                acc = .bool(try object.LooseEquals(f.regs[int(ins.A)], acc))
            case .testNe:
                acc = .bool(!(try object.LooseEquals(f.regs[int(ins.A)], acc)))
            case .testStrictEq:
                acc = .bool(object.StrictEquals(f.regs[int(ins.A)], acc))
            case .testStrictNe:
                acc = .bool(!object.StrictEquals(f.regs[int(ins.A)], acc))
            case .testLt:
                let l = f.regs[int(ins.A)]
                if case .number(let a) = l, case .number(let b) = acc {
                    acc = .bool(a < b)
                } else {
                    acc = .bool((try object.LessThan(l, acc, leftFirst: true)) ?? false)
                }
            case .testGt:
                let l = f.regs[int(ins.A)]
                if case .number(let a) = l, case .number(let b) = acc {
                    acc = .bool(a > b)
                } else {
                    acc = .bool((try object.LessThan(acc, l, leftFirst: false)) ?? false)
                }
            case .testLe:
                let l = f.regs[int(ins.A)]
                if case .number(let a) = l, case .number(let b) = acc {
                    acc = .bool(a <= b)
                } else {
                    let r = try object.LessThan(acc, l, leftFirst: false)
                    acc = .bool(r == nil ? false : !r!)
                }
            case .testGe:
                let l = f.regs[int(ins.A)]
                if case .number(let a) = l, case .number(let b) = acc {
                    acc = .bool(a >= b)
                } else {
                    let r = try object.LessThan(l, acc, leftFirst: true)
                    acc = .bool(r == nil ? false : !r!)
                }
            case .testIn:
                guard case .object(let o) = acc else {
                    let k = f.regs[int(ins.A)]
                    var ks = "?"
                    if let s = try? object.ToString(k) { ks = s.String }
                    throw object.ThrowTypeError("Cannot use 'in' operator to search for '\(ks)' in \(describeIn(acc))")
                }
                acc = .bool(try o.HasProperty(try object.ToPropertyKey(f.regs[int(ins.A)])))
            case .testInstanceOf:
                acc = .bool(try object.InstanceOf(f.regs[int(ins.A)], acc))

            // Unary operators.
            case .inc:
                if case .number(let d) = acc { acc = .number(d + 1) } else if case .bigint(let b) = acc { acc = .bigint(value.BigInt.Add(b, value.BigInt.One)) }
            case .dec:
                if case .number(let d) = acc { acc = .number(d - 1) } else if case .bigint(let b) = acc { acc = .bigint(value.BigInt.Sub(b, value.BigInt.One)) }
            case .negate:
                if case .number(let d) = acc {
                    acc = .number(-d)
                } else {
                    let n = try object.ToNumeric(acc)
                    if case .bigint(let b) = n { acc = .bigint(b.Negate()) } else if case .number(let d) = n { acc = .number(-d) }
                }
            case .bitNot:
                let n = try object.ToNumeric(acc)
                if case .bigint(let b) = n { acc = .bigint(b.BitNot()) } else if case .number(let d) = n { acc = .number(float64(~value.DoubleToInt32(d))) }
            case .not:
                acc = .bool(!acc.Truthy)
            case .typeOf:
                acc = object.TypeOfValue(acc)
            case .toNumeric:
                if !acc.IsNumber { acc = try object.ToNumeric(acc) }
            case .toNumber:
                if !acc.IsNumber { acc = .number(try object.ToNumber(acc)) }
            case .toString:
                if !acc.IsString { acc = .string(try object.ToString(acc)) }

            // Control flow.
            case .jump:
                pc = int(ins.A)
            case .jumpIfTrue:
                if acc.Truthy { pc = int(ins.A) }
            case .jumpIfFalse:
                if !acc.Truthy { pc = int(ins.A) }
            case .jumpIfNullish:
                if acc.IsNullish { pc = int(ins.A) }
            case .jumpIfNotNullish:
                if !acc.IsNullish { pc = int(ins.A) }
            case .jumpIfUndefined:
                if acc.IsUndefined { pc = int(ins.A) }
            case .jumpIfNotUndefined:
                if !acc.IsUndefined { pc = int(ins.A) }
            case .jumpIfEmpty:
                if acc.IsEmpty { pc = int(ins.A) }
            case .returnOp:
                f.acc = acc
                f.pc = pc
                return .returned(acc)
            case .throwOp:
                throw object.Completion(acc)
            case .throwError:
                let msg = constString(consts[int(ins.A)]).String
                switch ins.B {
                case 1: throw object.ThrowReferenceError(msg)
                case 2: throw object.ThrowSyntaxError(msg)
                case 3: throw object.ThrowRangeError(msg)
                default: throw object.ThrowTypeError(msg)
                }

            // Calls.
            case .call, .callMethod, .callSpread:
                let callee = f.regs[int(ins.A)]
                var thisV: Value = .undefined
                var args: [Value]
                if ins.Op == .call {
                    args = argsFrom(f, int(ins.B), int(ins.C))
                } else if ins.Op == .callMethod {
                    thisV = f.regs[int(ins.B)]
                    args = argsFrom(f, int(ins.B) + 1, int(ins.C))
                } else {
                    if ins.B >= 0 { thisV = f.regs[int(ins.B)] }
                    args = try spreadArgs(f.regs[int(ins.C)])
                }
                if let fn = inlineCallee(callee) {
                    f.pc = pc
                    f.acc = acc
                    return .call(makeFrame(fn, this: thisFor(fn, thisV), args: args, newTarget: .undefined))
                }
                acc = try callValue(f, callee, thisV, args)
            case .callEval:
                acc = try callEval(f, f.regs[int(ins.A)], argsFrom(f, int(ins.B), int(ins.C)))
            case .construct, .constructSpread:
                let callee = f.regs[int(ins.A)]
                let args = ins.Op == .construct ? argsFrom(f, int(ins.B), int(ins.C)) : try spreadArgs(f.regs[int(ins.B)])
                if let callFrame = try inlineConstruct(callee, args) {
                    f.pc = pc
                    f.acc = acc
                    return .call(callFrame)
                }
                acc = try construct(f, callee, args)
            case .superCall:
                acc = try superCall(f, argsFrom(f, int(ins.B), int(ins.C)))
            case .superCallSpread:
                acc = try superCall(f, try spreadArgs(f.regs[int(ins.B)]))
            case .superCallForward:
                acc = try superCall(f, f.args)

            // Literals.
            case .createObject:
                acc = .object(object.JSObject(proto: f.realm.ObjectPrototype))
            case .createArray:
                acc = .object(object.ArrayObject(proto: f.realm.ArrayPrototype))
            case .arrayPush:
                if case .object(let o) = f.regs[int(ins.A)], let arr = o as? object.ArrayObject { arr.Push(acc) }
            case .arrayHole:
                if case .object(let o) = f.regs[int(ins.A)], let arr = o as? object.ArrayObject {
                    arr.Dense.append(.empty)
                    arr.Length += 1
                }
            case .arraySpread:
                if case .object(let o) = f.regs[int(ins.A)], let arr = o as? object.ArrayObject {
                    for v in try object.IterableToList(acc) { arr.Push(v) }
                }
            case .createRegExp:
                guard let make = f.realm.CreateRegExp else { throw object.ThrowSyntaxError("RegExp is not available") }
                acc = .object(try make(constString(consts[int(ins.A)]), constString(consts[int(ins.B)])))
            case .createClosure:
                if case .function(let t) = consts[int(ins.A)] {
                    acc = .object(makeClosure(f, t))
                }
            case .getTemplateObject:
                if case .template(let info) = consts[int(ins.A)] {
                    acc = .object(templateObject(f.realm, info))
                }

            // Classes.
            case .createClass:
                acc = try createClass(f, ins)
            case .addField:
                if case .object(let o) = f.regs[int(ins.A)], let ctor = o as? object.JSFunction {
                    let k = try object.ToPropertyKey(f.regs[int(ins.B)])
                    var initFn: object.JSObject? = nil
                    if ins.C >= 0, case .object(let fo) = f.regs[int(ins.C)] { initFn = fo }
                    ctor.Fields.append(object.ClassField(key: k, initializer: initFn))
                }
            case .addPrivateMethod:
                if case .object(let o) = f.regs[int(ins.A)], let ctor = o as? object.JSFunction, case .symbol(let s) = f.regs[int(ins.B)], case .object(let fn) = acc {
                    addPrivateMethod(&ctor.PrivateMethods, s, fn, int(ins.C))
                }
            case .addStaticPrivateMethod:
                if case .object(let target) = f.regs[int(ins.A)], case .symbol(let s) = f.regs[int(ins.B)], case .object(let fn) = acc {
                    var list: [object.PrivateMethod] = []
                    let existing = target.PrivateFind(s)
                    if existing >= 0, let slot = target.OwnSlot(.symbol(s)) {
                        let pm = object.PrivateMethod(name: s)
                        pm.Getter = slot.Getter
                        pm.Setter = slot.Setter
                        list.append(pm)
                    }
                    addPrivateMethod(&list, s, fn, int(ins.C))
                    installPrivateMethod(target, list[list.count - 1])
                }
            case .initFields:
                if let fn = activeFunction(f), case .object(let o) = try thisOf(f) {
                    try initializeInstanceElements(o, fn)
                }
            case .newPrivateName:
                acc = .symbol(value.Symbol(constString(consts[int(ins.A)]), isPrivate: true))

            // Iteration.
            case .getIterator, .getAsyncIterator:
                let r = ins.Op == .getIterator ? try object.GetIterator(acc) : try object.GetAsyncIterator(acc)
                f.regs[int(ins.A)] = .object(r.Iterator)
                f.regs[int(ins.A) + 1] = r.NextMethod
                f.regs[int(ins.A) + 2] = .bool(false)
            case .iteratorStep:
                let a = int(ins.A)
                if f.regs[a + 2].Truthy {
                    pc = int(ins.B)
                    break
                }
                do {
                    let res = try callValue(f, f.regs[a + 1], f.regs[a], [])
                    guard case .object(let ro) = res else {
                        throw object.ThrowTypeError("Iterator result \(object.Describe(res)) is not an object")
                    }
                    if try ro.Get(value.PropertyKey.Named("done"), res).Truthy {
                        f.regs[a + 2] = .bool(true)
                        pc = int(ins.B)
                    } else {
                        acc = try ro.Get(value.PropertyKey.Named("value"), res)
                    }
                } catch {
                    f.regs[a + 2] = .bool(true)
                    throw error
                }
            case .iteratorNext:
                let a = int(ins.A)
                acc = try callValue(f, f.regs[a + 1], f.regs[a], [acc])
            case .iteratorResult:
                let a = int(ins.A)
                guard case .object(let ro) = acc else {
                    throw object.ThrowTypeError("Iterator result \(object.Describe(acc)) is not an object")
                }
                if try ro.Get(value.PropertyKey.Named("done"), acc).Truthy {
                    f.regs[a + 2] = .bool(true)
                    pc = int(ins.B)
                } else {
                    acc = try ro.Get(value.PropertyKey.Named("value"), acc)
                }
            case .iteratorClose:
                let a = int(ins.A)
                if !f.regs[a + 2].Truthy, case .object(let it) = f.regs[a] {
                    f.regs[a + 2] = .bool(true)
                    try object.IteratorClose(object.IteratorRecord(iterator: it, next: f.regs[a + 1]))
                }
            case .iteratorCloseThrow:
                let a = int(ins.A)
                if !f.regs[a + 2].Truthy, case .object(let it) = f.regs[a] {
                    f.regs[a + 2] = .bool(true)
                    object.IteratorCloseOnThrow(object.IteratorRecord(iterator: it, next: f.regs[a + 1]))
                }
            case .asyncIteratorClose:
                let a = int(ins.A)
                if f.regs[a + 2].Truthy {
                    pc = int(ins.B)
                    break
                }
                f.regs[a + 2] = .bool(true)
                let ret = try object.GetMethod(f.regs[a], value.PropertyKey.Named("return"))
                if ret.IsUndefined {
                    pc = int(ins.B)
                } else {
                    acc = try object.Call(ret, f.regs[a], [])
                }
            case .iteratorToArray:
                let a = int(ins.A)
                let arr = object.ArrayObject(proto: f.realm.ArrayPrototype)
                if !f.regs[a + 2].Truthy, case .object(let it) = f.regs[a] {
                    let rec = object.IteratorRecord(iterator: it, next: f.regs[a + 1])
                    do {
                        while let v = try object.IteratorStepValue(rec) { arr.Push(v) }
                    } catch {
                        f.regs[a + 2] = .bool(true)
                        throw error
                    }
                    f.regs[a + 2] = .bool(true)
                }
                acc = .object(arr)
            case .forInPrepare:
                f.regs[int(ins.A)] = .object(ForInIterator(try object.ToObject(acc)))
            case .forInNext:
                if case .object(let o) = f.regs[int(ins.A)], let it = o as? ForInIterator, let k = try it.Next() {
                    acc = k
                } else {
                    pc = int(ins.B)
                }

            // Generators and async functions.
            case .generatorStart:
                f.pc = pc
                f.acc = acc
                return .started
            case .yieldOp:
                f.yieldModeReg = ins.A
                f.yieldValueReg = ins.B
                f.pc = pc
                f.acc = acc
                return .yielded(acc, ins.C == 1)
            case .awaitOp:
                f.pc = pc
                f.acc = acc
                return .awaited(acc)
            case .asyncReturnAwait:
                break

            // Explicit resource management.
            case .createDisposeScope:
                f.regs[int(ins.A)] = .object(DisposeScope(proto: nil))
            case .addDisposable:
                if case .object(let o) = f.regs[int(ins.A)], let ds = o as? DisposeScope {
                    try ds.Add(acc, async: ins.B == 1)
                }
            case .disposeNext:
                acc = .number(0)
                if case .object(let o) = f.regs[int(ins.A)], let ds = o as? DisposeScope {
                    let (status, v) = ds.Next(f.realm)
                    acc = .number(float64(status))
                    f.regs[int(ins.B)] = v
                }
            case .disposeError:
                if case .object(let o) = f.regs[int(ins.A)], let ds = o as? DisposeScope {
                    ds.Record(acc, f.realm)
                }
            case .disposeFinish:
                if case .object(let o) = f.regs[int(ins.A)], let ds = o as? DisposeScope, let e = ds.Error {
                    throw object.Completion(e)
                }

            // Modules.
            case .importCall:
                throw object.ThrowTypeError("import() is not supported in scripts yet")
            case .importMeta:
                throw object.ThrowSyntaxError("Cannot use 'import.meta' outside a module")
            }
        }
    }

    // MARK: helpers

    func constValue(_ c: bytecode.Constant) -> Value {
        switch c {
        case .number(let d): return .number(d)
        case .string(let s): return .string(s)
        case .key(let k): return object.KeyToValue(k)
        case .bigint(let b): return .bigint(b)
        default: return .undefined
        }
    }

    func constString(_ c: bytecode.Constant) -> str.JSString {
        switch c {
        case .string(let s): return s
        case .key(let k): return k.AsString
        default: return str.JSString.Empty
        }
    }

    func constKey(_ c: bytecode.Constant) -> value.PropertyKey {
        switch c {
        case .key(let k): return k
        case .string(let s): return value.PropertyKey.FromString(s)
        default: return value.PropertyKey.Named("")
        }
    }

    func tdz(_ c: bytecode.Constant) -> object.Completion {
        return object.ThrowReferenceError("Cannot access '\(constString(c).String)' before initialization")
    }

    func contextAt(_ f: Frame, _ depth: int32) -> object.Context {
        var c = f.ctx!
        var d = depth
        while d > 0 {
            c = c.Parent!
            d -= 1
        }
        return c
    }

    func argsFrom(_ f: Frame, _ first: int, _ n: int) -> [Value] {
        if n == 0 { return [] }
        var out: [Value] = []
        out.reserveCapacity(n)
        var i = 0
        while i < n {
            out.append(f.regs[first + i])
            i += 1
        }
        return out
    }

    func spreadArgs(_ v: Value) throws -> [Value] {
        if case .object(let o) = v, let arr = o as? object.ArrayObject {
            var out = arr.Dense
            var i = 0
            while i < out.count {
                if out[i].IsEmpty { out[i] = .undefined }
                i += 1
            }
            return out
        }
        return []
    }

    func arith(_ op: object.ArithOp, _ l: Value, _ r: Value) throws -> Value {
        if case .number(let a) = l, case .number(let b) = r {
            return .number(object.NumberOp(op, a, b))
        }
        return try object.Arithmetic(op, l, r)
    }

    func describeIn(_ v: Value) -> string {
        switch v {
        case .string(let s): return s.String
        default: return object.Describe(v)
        }
    }

    func nameOfPrivate(_ v: Value) -> string {
        if case .symbol(let s) = v { return s.DescriptiveString }
        return "#?"
    }

    func superBase(_ f: Frame) throws -> object.JSObject {
        guard let fn = activeFunction(f), let home = fn.HomeObject else {
            throw object.ThrowSyntaxError("'super' keyword unexpected here")
        }
        guard let p = try home.GetPrototypeOf() else {
            throw object.ThrowTypeError("Cannot read properties of null")
        }
        return p
    }

    func privateGet(_ base: Value, _ name: Value) throws -> Value {
        guard case .symbol(let s) = name else { return .undefined }
        guard case .object(let o) = base, let slot = o.OwnSlot(.symbol(s)) else {
            throw object.ThrowTypeError("Cannot read private member \(s.DescriptiveString) from an object whose class did not declare it")
        }
        if slot.IsAccessor {
            guard let g = slot.Getter else {
                throw object.ThrowTypeError("'\(s.DescriptiveString)' was defined without a getter")
            }
            return try g.Call(base, [])
        }
        return slot.Value
    }

    func privateSet(_ base: Value, _ name: Value, _ v: Value) throws {
        guard case .symbol(let s) = name else { return }
        guard case .object(let o) = base, let slot = o.OwnSlot(.symbol(s)) else {
            throw object.ThrowTypeError("Cannot write private member \(s.DescriptiveString) to an object whose class did not declare it")
        }
        if slot.IsAccessor {
            guard let st = slot.Setter else {
                throw object.ThrowTypeError("'\(s.DescriptiveString)' was defined without a setter")
            }
            _ = try st.Call(base, [v])
            return
        }
        if !slot.Writable {
            throw object.ThrowTypeError("Private method '\(s.DescriptiveString)' is not writable")
        }
        var ns = slot
        ns.Value = v
        o.store(.symbol(s), ns)
    }

    func addPrivateMethod(_ list: inout [object.PrivateMethod], _ s: value.Symbol, _ fn: object.JSObject, _ kind: int) {
        var pm: object.PrivateMethod? = nil
        for m in list where m.Name === s { pm = m }
        if pm == nil {
            pm = object.PrivateMethod(name: s)
            list.append(pm!)
        }
        object.SetFunctionName(fn, .symbol(s), prefix: kind == 1 ? "get" : (kind == 2 ? "set" : ""))
        switch kind {
        case 1: pm!.Getter = fn
        case 2: pm!.Setter = fn
        default: pm!.Method = fn
        }
    }

    func construct(_ f: Frame, _ callee: Value, _ args: [Value]) throws -> Value {
        guard case .object(let o) = callee, o.IsConstructor else {
            throw object.ThrowTypeError("\(calleeText(f)) is not a constructor")
        }
        return try o.Construct(args, o)
    }

    func superCall(_ f: Frame, _ args: [Value]) throws -> Value {
        guard let fe = f.funcEnv, let active = fe.Function else {
            throw object.ThrowSyntaxError("'super' keyword unexpected here")
        }
        guard let parent = try active.GetPrototypeOf(), parent.IsConstructor else {
            throw object.ThrowTypeError("Super constructor \(object.Describe(active.Proto == nil ? .null : .object(active.Proto!))) of anonymous class is not a constructor")
        }
        guard case .object(let nt) = fe.NewTarget else {
            throw object.ThrowSyntaxError("'super' keyword unexpected here")
        }
        let result = try parent.Construct(args, nt)
        if !fe.This.IsEmpty {
            throw object.ThrowReferenceError("Super constructor may only be called once")
        }
        fe.This = result
        if f.fn === active { f.this = result }
        if case .object(let o) = result {
            try initializeInstanceElements(o, active)
        }
        return result
    }

    /// makeClosure instantiates a function template (§10.2.3 OrdinaryFunctionCreate and friends).
    func makeClosure(_ f: Frame, _ t: bytecode.FunctionTemplate) -> object.JSFunction {
        let r = f.realm
        var proto = r.FunctionPrototype
        if t.IsAsync && t.IsGenerator {
            proto = r.AsyncGeneratorFunctionPrototype
        } else if t.IsGenerator {
            proto = r.GeneratorFunctionPrototype
        } else if t.IsAsync {
            proto = r.AsyncFunctionPrototype
        }
        let fn = object.JSFunction(template: t, env: f.ctx, realm: r, proto: proto)
        if t.IsArrow {
            fn.FuncEnv = funcEnvOf(f)
        }
        fn.DefineData(value.PropertyKey.Named("length"), .number(float64(t.Length)), writable: false, enumerable: false, configurable: true)
        fn.DefineData(value.PropertyKey.Named("name"), .string(t.Name), writable: false, enumerable: false, configurable: true)
        if t.IsGenerator {
            let p = object.JSObject(proto: t.IsAsync ? r.AsyncGeneratorPrototype : r.GeneratorPrototype)
            fn.DefineData(value.PropertyKey.Named("prototype"), .object(p), writable: true, enumerable: false, configurable: false)
        } else if t.Kind == .normal && !t.IsAsync {
            object.MakeConstructor(fn, realm: r)
        }
        return fn
    }

    /// createClass is the part of ClassDefinitionEvaluation that makes the
    /// constructor and prototype (§15.7.14 steps 5-16).
    func createClass(_ f: Frame, _ ins: bytecode.Instruction) throws -> Value {
        let r = f.realm
        var protoParent: object.JSObject? = r.ObjectPrototype
        var ctorParent: object.JSObject = r.FunctionPrototype
        if ins.B >= 0 {
            let sup = f.regs[int(ins.B)]
            if sup.IsNull {
                protoParent = nil
            } else {
                guard case .object(let so) = sup, so.IsConstructor else {
                    throw object.ThrowTypeError("Class extends value \(object.Describe(sup)) is not a constructor or null")
                }
                let pp = try so.Get(value.PropertyKey.Named("prototype"), sup)
                if case .object(let ppo) = pp {
                    protoParent = ppo
                } else if pp.IsNull {
                    protoParent = nil
                } else {
                    throw object.ThrowTypeError("Class extends value does not have valid prototype property \(object.Describe(pp))")
                }
                ctorParent = so
            }
        }
        guard case .function(let t) = f.t.Constants[int(ins.A)] else { return .undefined }
        let proto = object.JSObject(proto: protoParent)
        let F = object.JSFunction(template: t, env: f.ctx, realm: r, proto: ctorParent)
        F.HomeObject = proto
        F.DefineData(value.PropertyKey.Named("length"), .number(float64(t.Length)), writable: false, enumerable: false, configurable: true)
        F.DefineData(value.PropertyKey.Named("name"), .string(t.Name), writable: false, enumerable: false, configurable: true)
        F.DefineData(value.PropertyKey.Named("prototype"), .object(proto), writable: false, enumerable: false, configurable: false)
        proto.DefineData(value.PropertyKey.Named("constructor"), .object(F), writable: true, enumerable: false, configurable: true)
        f.regs[int(ins.C)] = .object(proto)
        return .object(F)
    }

    func templateObject(_ r: object.Realm, _ info: bytecode.TemplateInfo) -> object.JSObject {
        if let o = r.TemplateMap[info.ID] { return o }
        var cooked: [Value] = []
        for c in info.Cooked {
            if let s = c { cooked.append(.string(s)) } else { cooked.append(.undefined) }
        }
        var raw: [Value] = []
        for s in info.Raw { raw.append(.string(s)) }
        let rawArr = object.CreateArrayFromList(r, raw)
        let arr = object.CreateArrayFromList(r, cooked)
        arr.DefineData(value.PropertyKey.Named("raw"), .object(rawArr), writable: false, enumerable: false, configurable: false)
        _ = try? object.SetIntegrityLevel(rawArr, frozen: true)
        _ = try? object.SetIntegrityLevel(arr, frozen: true)
        r.TemplateMap[info.ID] = arr
        return arr
    }

    /// makeArguments creates the arguments object (§10.4.4.6, §10.4.4.7).
    func makeArguments(_ f: Frame, mapped: bool) -> object.JSObject {
        let r = f.realm
        let a = object.ArgumentsObject(proto: r.ObjectPrototype)
        var i = 0
        while i < f.args.count {
            a.DefineData(.index(uint32(i)), f.args[i])
            i += 1
        }
        a.DefineData(value.PropertyKey.Named("length"), .number(float64(f.args.count)), writable: true, enumerable: false, configurable: true)
        if let iter = r.Intrinsics["ArrayValues"] {
            a.DefineData(.symbol(value.SymIterator), .object(iter), writable: true, enumerable: false, configurable: true)
        }
        if mapped, let fn = f.fn {
            a.DefineData(value.PropertyKey.Named("callee"), .object(fn), writable: true, enumerable: false, configurable: true)
            var map: [int] = []
            var j = 0
            while j < f.args.count {
                map.append(j < f.t.MappedParams.count ? f.t.MappedParams[j] : -1)
                j += 1
            }
            a.Map = map
            // The parameters live in the function's own context.
            var c = f.ctx
            var d = f.ctxDepth
            while d > 0 { c = c?.Parent; d -= 1 }
            a.Env = c
        } else {
            let thrower = r.ThrowTypeError
            a.DefineAccessorDirect(value.PropertyKey.Named("callee"), getter: thrower, setter: thrower, enumerable: false, configurable: false)
        }
        return a
    }
}
