package codegen

import (
    "js/ast"
    "js/bytecode"
    "js/str"
    "js/token"
    "js/value"
)

/// Reference is an evaluated assignment target: where to load and store.
enum Reference {
    case identifier(ast.Identifier)
    case named(int32, string)          // object register, name
    case keyed(int32, int32)           // object register, key register
    case privateField(int32, int32)    // object register, private name register
    case superProperty(int32)          // key register
}

extension Builder {
    /// exprNamed compiles an expression that an anonymous function or class
    /// takes its name from (NamedEvaluation, §8.4.5).
    func exprNamed(_ e: ast.Expr, _ name: string?) throws {
        if let n = name {
            switch ast.StripParens(e) {
            case .function(let f) where f.Name.isEmpty:
                try compileClosure(f, nameHint: n)
                return
            case .classExpr(let c) where c.Name.isEmpty:
                try classDef(c, nameHint: n)
                return
            default:
                break
            }
        }
        try expr(e)
    }

    /// exprToReg compiles e into a fresh temporary.
    func exprToReg(_ e: ast.Expr) throws -> int32 {
        try expr(e)
        let r = temp()
        emit(.star, r)
        return r
    }

    func expr(_ e: ast.Expr) throws {
        switch e {
        case .number(let n):
            loadNumber(n.Value)
        case .bigint(let b):
            emit(.ldaConst, constIndex(.bigint(value.BigInt.ParseLiteral(b.Digits))))
        case .string(let s):
            emit(.ldaConst, jsStrConst(s.Value))
        case .template(let t):
            try template(t)
        case .taggedTemplate(let t):
            try taggedTemplate(t)
        case .regex(let r):
            emit(.createRegExp, jsStrConst(unicodeOf(r.Pattern)), strConst(r.Flags))
        case .boolean(let b):
            emit(b.Value ? .ldaTrue : .ldaFalse)
        case .nullLit:
            emit(.ldaNull)
        case .hole:
            emit(.ldaUndefined)
        case .identifier(let id):
            loadIdentifier(id)
        case .thisExpr:
            emit(.ldaThis)
        case .newTarget:
            emit(.ldaNewTarget)
        case .importMeta:
            emit(.importMeta)
        case .superMember(let s):
            let m = mark()
            let k = try superKey(s)
            emit(.getSuper, k)
            release(m)
        case .superCall(let c):
            try superCall(c)
        case .array(let a):
            try arrayLiteral(a)
        case .object(let o):
            try objectLiteral(o)
        case .function(let f):
            try compileClosure(f, nameHint: nil)
        case .classExpr(let c):
            try classDef(c, nameHint: nil)
        case .unary(let u):
            try unary(u)
        case .update(let u):
            try update(u)
        case .binary(let b):
            try binary(b)
        case .logical(let l):
            let end = newLabel()
            try expr(l.Left)
            switch l.Op {
            case .logicalAnd: jump(.jumpIfFalse, end)
            case .logicalOr: jump(.jumpIfTrue, end)
            default: jump(.jumpIfNotNullish, end)
            }
            try expr(l.Right)
            bind(end)
        case .assign(let a):
            try assign(a)
        case .conditional(let c):
            let elseL = newLabel()
            let end = newLabel()
            try condition(c.Test, falseLabel: elseL)
            try expr(c.Consequent)
            jump(.jump, end)
            bind(elseL)
            try expr(c.Alternate)
            bind(end)
        case .call(let c):
            try call(c)
        case .newExpr(let n):
            try newExpr(n)
        case .member(let m):
            let mk = mark()
            try expr(m.Object)
            if m.Optional { jump(.jumpIfNullish, optionalExits[optionalExits.count - 1]) }
            let obj = temp()
            emit(.star, obj)
            try memberGet(m, obj)
            release(mk)
        case .optionalChain(let o):
            let exit = newLabel()
            let end = newLabel()
            optionalExits.append(exit)
            try expr(o.Expression)
            _ = optionalExits.removeLast()
            jump(.jump, end)
            bind(exit)
            emit(.ldaUndefined)
            bind(end)
        case .sequence(let q):
            for x in q.Expressions { try expr(x) }
        case .spread(let s):
            throw CompileError.syntax(message: "Unexpected token '...'", pos: s.At)
        case .yieldExpr(let y):
            try yieldExpr(y)
        case .awaitExpr(let a):
            try expr(a.Argument)
            emit(.awaitOp)
        case .importCall(let i):
            try expr(i.Source)
            emit(.importCall)
        case .privateIn(let p):
            let m = mark()
            try expr(p.Right)
            let obj = temp()
            emit(.star, obj)
            let name = temp()
            loadPrivateName(p.PrivateBinding, p.Name)
            emit(.star, name)
            emit(.ldar, obj)
            emit(.privateIn, name)
            release(m)
        case .paren(let p):
            try expr(p.Expression)
        }
    }

    /// noteCallee records how the next call's callee reads, for errors.
    func noteCallee(_ e: ast.Expr) {
        t.CalleeText[t.Code.count] = render(e)
    }

    /// render prints an expression the way V8's messages show a callee.
    func render(_ e: ast.Expr) -> string {
        switch e {
        case .identifier(let id): return id.Name
        case .thisExpr: return "this"
        case .paren(let p): return render(p.Expression)
        case .member(let m):
            let o = render(m.Object)
            if m.Private { return o + ".#" + m.Name }
            if m.Computed {
                if let p = m.Property {
                    switch p {
                    case .number(let n): return o + "[" + formatIndex(n.Value) + "]"
                    case .string(let s): return o + "[\"" + str.JSString(s.Value).String + "\"]"
                    case .identifier(let id): return o + "[" + id.Name + "]"
                    default: return o + "[...]"
                    }
                }
            }
            return o + "." + m.Name
        case .superMember(let s):
            if !s.Computed, case .string(let k) = s.Property { return "(intermediate value)." + str.JSString(k.Value).String }
            return "(intermediate value)"
        case .optionalChain(let o): return render(o.Expression)
        default: return "(intermediate value)"
        }
    }

    func formatIndex(_ d: float64) -> string {
        if d == d.rounded(.towardZero) && d >= 0 && d < 1e15 { return "\(int64(d))" }
        return "\(d)"
    }

    func unicodeOf(_ s: string) -> [uint16] {
        return str.JSString.From(s).Units
    }

    // MARK: members

    /// memberGet loads obj[m] into the accumulator (obj in a register).
    func memberGet(_ m: ast.MemberExpr, _ obj: int32) throws {
        if m.Private {
            let name = temp()
            loadPrivateName(m.PrivateBinding, m.Name)
            emit(.star, name)
            emit(.getPrivate, obj, name)
        } else if m.Computed {
            try expr(m.Property!)
            emit(.getKeyed, obj)
        } else {
            emit(.getNamed, obj, keyConst(m.Name))
        }
    }

    func loadPrivateName(_ b: ast.Binding?, _ name: string) {
        if let pb = b {
            loadBinding(pb, name: "#" + name)
        } else {
            emit(.ldaUndefined)
        }
    }

    /// superKey evaluates a super property's key into a register.
    func superKey(_ s: ast.SuperMember) throws -> int32 {
        let k = temp()
        try expr(s.Property)
        if s.Computed { emit(.toPropertyKey) }
        emit(.star, k)
        return k
    }

    // MARK: operators

    func unary(_ u: ast.UnaryExpr) throws {
        switch u.Op {
        case .sub:
            try expr(u.Argument)
            emit(.negate)
        case .add:
            try expr(u.Argument)
            emit(.toNumber)
        case .logicalNot:
            try expr(u.Argument)
            emit(.not)
        case .bitNot:
            try expr(u.Argument)
            emit(.bitNot)
        case .kTypeof:
            if case .identifier(let id) = ast.StripParens(u.Argument) {
                loadIdentifier(id, typeofOperand: true)
            } else {
                try expr(u.Argument)
            }
            emit(.typeOf)
        case .kVoid:
            try expr(u.Argument)
            emit(.ldaUndefined)
        case .kDelete:
            try deleteExpr(u.Argument)
        default:
            try expr(u.Argument)
        }
    }

    func deleteExpr(_ arg: ast.Expr) throws {
        let m = mark()
        defer { release(m) }
        switch ast.StripParens(arg) {
        case .member(let mem):
            try expr(mem.Object)
            let obj = temp()
            emit(.star, obj)
            if mem.Computed {
                try expr(mem.Property!)
            } else {
                emit(.ldaConst, strConst(mem.Name))
            }
            emit(.deleteProperty, obj, t.Strict ? 1 : 0)
        case .optionalChain(let o):
            // delete a?.b: true when a is nullish.
            let exit = newLabel()
            let end = newLabel()
            optionalExits.append(exit)
            if case .member(let mem) = o.Expression {
                try expr(mem.Object)
                if mem.Optional { jump(.jumpIfNullish, exit) }
                let obj = temp()
                emit(.star, obj)
                if mem.Computed { try expr(mem.Property!) } else { emit(.ldaConst, strConst(mem.Name)) }
                emit(.deleteProperty, obj, t.Strict ? 1 : 0)
            } else {
                try expr(o.Expression)
                emit(.ldaTrue)
            }
            _ = optionalExits.removeLast()
            jump(.jump, end)
            bind(exit)
            emit(.ldaTrue)
            bind(end)
        case .identifier(let id):
            if id.Binding != nil && !id.Dynamic {
                emit(.ldaFalse)
            } else {
                emit(.deleteLookup, strConst(id.Name))
            }
        case .superMember(let s):
            try expr(s.Property)
            throwError("Unsupported reference to 'super'", 1)
        default:
            try expr(arg)
            emit(.ldaTrue)
        }
    }

    func binaryOp(_ op: token.TokenKind) -> bytecode.Opcode {
        switch op {
        case .add: return .add
        case .sub: return .sub
        case .mul: return .mul
        case .div: return .div
        case .mod: return .mod
        case .exp: return .exp
        case .bitAnd: return .bitAnd
        case .bitOr: return .bitOr
        case .bitXor: return .bitXor
        case .shl: return .shl
        case .shr: return .sar
        case .ushr: return .shr
        case .eq: return .testEq
        case .notEq: return .testNe
        case .strictEq: return .testStrictEq
        case .strictNotEq: return .testStrictNe
        case .less: return .testLt
        case .greater: return .testGt
        case .lessEq: return .testLe
        case .greaterEq: return .testGe
        case .kIn: return .testIn
        case .kInstanceof: return .testInstanceOf
        case .addAssign: return .add
        case .subAssign: return .sub
        case .mulAssign: return .mul
        case .divAssign: return .div
        case .modAssign: return .mod
        case .expAssign: return .exp
        case .andAssign: return .bitAnd
        case .orAssign: return .bitOr
        case .xorAssign: return .bitXor
        case .shlAssign: return .shl
        case .shrAssign: return .sar
        case .ushrAssign: return .shr
        default: return .nop
        }
    }

    func binary(_ b: ast.BinaryExpr) throws {
        let m = mark()
        let l = try exprToReg(b.Left)
        try expr(b.Right)
        emit(binaryOp(b.Op), l)
        release(m)
    }

    // MARK: assignment

    /// reference evaluates a simple target's object and key.
    func reference(_ p: ast.Pattern) throws -> Reference {
        guard case .member(let e) = p else {
            if case .identifier(let id) = p { return .identifier(id) }
            throw CompileError.syntax(message: "Invalid left-hand side in assignment", pos: 0)
        }
        switch ast.StripParens(e) {
        case .identifier(let id):
            return .identifier(id)
        case .member(let m):
            let obj = try exprToReg(m.Object)
            if m.Private {
                let n = temp()
                loadPrivateName(m.PrivateBinding, m.Name)
                emit(.star, n)
                return .privateField(obj, n)
            }
            if m.Computed {
                try expr(m.Property!)
                emit(.toPropertyKey)
                let k = temp()
                emit(.star, k)
                return .keyed(obj, k)
            }
            return .named(obj, m.Name)
        case .superMember(let s):
            return .superProperty(try superKey(s))
        default:
            throw CompileError.syntax(message: "Invalid left-hand side in assignment", pos: ast.ExprPos(e))
        }
    }

    func loadReference(_ r: Reference) {
        switch r {
        case .identifier(let id): loadIdentifier(id)
        case .named(let o, let n): emit(.getNamed, o, keyConst(n))
        case .keyed(let o, let k):
            emit(.ldar, k)
            emit(.getKeyed, o)
        case .privateField(let o, let n): emit(.getPrivate, o, n)
        case .superProperty(let k): emit(.getSuper, k)
        }
    }

    /// storeReference stores the accumulator, leaving it there.
    func storeReference(_ r: Reference) {
        switch r {
        case .identifier(let id): storeIdentifier(id, initialize: false)
        case .named(let o, let n): emit(.setNamed, o, keyConst(n), t.Strict ? 1 : 0)
        case .keyed(let o, let k): emit(.setKeyed, o, k, t.Strict ? 1 : 0)
        case .privateField(let o, let n): emit(.setPrivate, o, n)
        case .superProperty(let k): emit(.setSuper, k)
        }
    }

    func assign(_ a: ast.AssignExpr) throws {
        let m = mark()
        defer { release(m) }
        switch a.Target {
        case .array, .object:
            try expr(a.Value)
            let v = temp()
            emit(.star, v)
            try bindPatternFromAcc(a.Target, initialize: false)
            emit(.ldar, v)
            return
        default:
            break
        }
        let ref = try reference(a.Target)
        var name: string? = nil
        if case .identifier(let id) = ref { name = id.Name }
        switch a.Op {
        case .assign:
            try exprNamed(a.Value, name)
            storeReference(ref)
        case .logicalAndAssign, .logicalOrAssign, .nullishAssign:
            let end = newLabel()
            loadReference(ref)
            if a.Op == .logicalAndAssign { jump(.jumpIfFalse, end) } else if a.Op == .logicalOrAssign { jump(.jumpIfTrue, end) } else { jump(.jumpIfNotNullish, end) }
            try exprNamed(a.Value, name)
            storeReference(ref)
            bind(end)
        default:
            loadReference(ref)
            let old = temp()
            emit(.star, old)
            try expr(a.Value)
            emit(binaryOp(a.Op), old)
            storeReference(ref)
        }
    }

    func update(_ u: ast.UpdateExpr) throws {
        let m = mark()
        defer { release(m) }
        let ref = try reference(.member(u.Argument))
        loadReference(ref)
        emit(.toNumeric)
        var old: int32 = -1
        if !u.Prefix {
            old = temp()
            emit(.star, old)
        }
        emit(u.Op == .inc ? .inc : .dec)
        storeReference(ref)
        if !u.Prefix { emit(.ldar, old) }
    }

    // MARK: calls

    /// args compiles arguments into consecutive registers starting at a
    /// fresh block; with a spread, into an array instead. It returns
    /// (first register, count, spread array register or -1).
    func argsToRegs(_ args: [ast.Expr], leading: int) throws -> (int32, int, int32) {
        var hasSpread = false
        for a in args { if case .spread = a { hasSpread = true } }
        if hasSpread {
            emit(.createArray)
            let arr = temp()
            emit(.star, arr)
            for a in args {
                if case .spread(let s) = a {
                    try expr(s.Argument)
                    emit(.arraySpread, arr)
                } else {
                    try expr(a)
                    emit(.arrayPush, arr)
                }
            }
            return (-1, 0, arr)
        }
        let first = temps(leading + args.count)
        var i = 0
        for a in args {
            try expr(a)
            emit(.star, first + int32(leading + i))
            i += 1
        }
        return (first, args.count, -1)
    }

    func call(_ c: ast.CallExpr) throws {
        let m = mark()
        defer { release(m) }
        at(c.At)
        let callee = ast.StripParens(c.Callee)
        if c.DirectEval, case .identifier(let id) = callee {
            loadIdentifier(id)
            let f = temp()
            emit(.star, f)
            let (first, n, spread) = try argsToRegs(c.Args, leading: 0)
            if spread >= 0 {
                emit(.callSpread, f, -1, spread)
            } else {
                emit(.callEval, f, first, int32(n))
            }
            return
        }
        // The callee and its this.
        var f: int32 = -1
        var thisReg: int32 = -1
        switch callee {
        case .member(let mem):
            try expr(mem.Object)
            if mem.Optional { jump(.jumpIfNullish, optionalExits[optionalExits.count - 1]) }
            thisReg = temp()
            emit(.star, thisReg)
            try memberGet(mem, thisReg)
            f = temp()
            emit(.star, f)
        case .superMember(let s):
            let k = try superKey(s)
            emit(.getSuper, k)
            f = temp()
            emit(.star, f)
            thisReg = temp()
            emit(.ldaThis)
            emit(.star, thisReg)
        case .identifier(let id) where id.Dynamic:
            thisReg = temp()
            emit(.ldaLookupThis, strConst(id.Name), thisReg)
            f = temp()
            emit(.star, f)
        default:
            try expr(c.Callee)
            f = temp()
            emit(.star, f)
        }
        if c.Optional {
            emit(.ldar, f)
            jump(.jumpIfNullish, optionalExits[optionalExits.count - 1])
        }
        if thisReg >= 0 {
            // CallMethod wants this and the arguments together.
            var hasSpread = false
            for a in c.Args { if case .spread = a { hasSpread = true } }
            if hasSpread {
                let (_, _, arr) = try argsToRegs(c.Args, leading: 0)
                noteCallee(c.Callee)
                emit(.callSpread, f, thisReg, arr)
            } else {
                let first = temps(1 + c.Args.count)
                emit(.ldar, thisReg)
                emit(.star, first)
                var i = 1
                for a in c.Args {
                    try expr(a)
                    emit(.star, first + int32(i))
                    i += 1
                }
                at(c.At)
                noteCallee(c.Callee)
                emit(.callMethod, f, first, int32(c.Args.count))
            }
        } else {
            let (first, n, spread) = try argsToRegs(c.Args, leading: 0)
            at(c.At)
            noteCallee(c.Callee)
            if spread >= 0 {
                emit(.callSpread, f, -1, spread)
            } else {
                emit(.call, f, first, int32(n))
            }
        }
    }

    func newExpr(_ n: ast.NewExpr) throws {
        let m = mark()
        defer { release(m) }
        let f = try exprToReg(n.Callee)
        let (first, count, spread) = try argsToRegs(n.Args, leading: 0)
        at(n.At)
        noteCallee(n.Callee)
        if spread >= 0 {
            emit(.constructSpread, f, spread)
        } else {
            emit(.construct, f, first, int32(count))
        }
    }

    func superCall(_ c: ast.SuperCall) throws {
        let m = mark()
        defer { release(m) }
        let (first, count, spread) = try argsToRegs(c.Args, leading: 0)
        at(c.At)
        if spread >= 0 {
            emit(.superCallSpread, 0, spread)
        } else {
            emit(.superCall, 0, first, int32(count))
        }
    }

    // MARK: literals

    func arrayLiteral(_ a: ast.ArrayLit) throws {
        let m = mark()
        defer { release(m) }
        emit(.createArray)
        let arr = temp()
        emit(.star, arr)
        for el in a.Elements {
            switch el {
            case .hole:
                emit(.arrayHole, arr)
            case .spread(let s):
                try expr(s.Argument)
                emit(.arraySpread, arr)
            default:
                try expr(el)
                emit(.arrayPush, arr)
            }
        }
        emit(.ldar, arr)
    }

    /// propertyKeyToReg evaluates a property key into a register.
    func propertyKeyToReg(_ k: ast.PropertyKey) throws -> int32 {
        let r = temp()
        switch k {
        case .named(let n):
            emit(.ldaConst, strConst(n))
        case .computed(let e):
            try expr(e)
            emit(.toPropertyKey)
        case .privateName(let n):
            emit(.ldaConst, strConst("#" + n))
        }
        emit(.star, r)
        return r
    }

    func objectLiteral(_ o: ast.ObjectLit) throws {
        let m = mark()
        defer { release(m) }
        emit(.createObject)
        let obj = temp()
        emit(.star, obj)
        for p in o.Properties {
            let pm = mark()
            switch p.Kind {
            case .spread:
                try expr(p.Value)
                emit(.copyDataProperties, obj, -1)
            case .protoSetter:
                try expr(p.Value)
                emit(.setProto, obj)
            case .initProp:
                if case .named(let n) = p.Key {
                    try exprNamed(p.Value, n)
                    emit(.defineNamed, obj, keyConst(n))
                } else {
                    let k = try propertyKeyToReg(p.Key)
                    try expr(p.Value)
                    if ast.IsAnonymousFunctionDefinition(ast.StripParens(p.Value)) {
                        emit(.setFunctionName, k, 0)
                    }
                    emit(.defineKeyed, obj, k)
                }
            case .method:
                let k = try propertyKeyToReg(p.Key)
                if case .function(let f) = p.Value {
                    try compileClosure(f, nameHint: keyHint(p.Key))
                }
                emit(.defineMethod, obj, k, 1)
            case .getter, .setter:
                let k = try propertyKeyToReg(p.Key)
                if case .function(let f) = p.Value {
                    try compileClosure(f, nameHint: nil)
                }
                emit(p.Kind == .getter ? .defineGetter : .defineSetter, obj, k, 1)
            }
            release(pm)
        }
        emit(.ldar, obj)
    }

    func keyHint(_ k: ast.PropertyKey) -> string? {
        if case .named(let n) = k { return n }
        if case .privateName(let n) = k { return "#" + n }
        return nil
    }

    func template(_ t: ast.TemplateLit) throws {
        let m = mark()
        defer { release(m) }
        let acc = temp()
        emit(.ldaConst, jsStrConst(t.Cooked[0] ?? []))
        emit(.star, acc)
        var i = 0
        while i < t.Exprs.count {
            try expr(t.Exprs[i])
            emit(.toString)
            emit(.add, acc)
            emit(.star, acc)
            if let cooked = t.Cooked[i + 1], !cooked.isEmpty {
                emit(.ldaConst, jsStrConst(cooked))
                emit(.add, acc)
                emit(.star, acc)
            }
            i += 1
        }
        emit(.ldar, acc)
    }

    func taggedTemplate(_ tt: ast.TaggedTemplate) throws {
        let m = mark()
        defer { release(m) }
        var cooked: [str.JSString?] = []
        var raw: [str.JSString] = []
        for c in tt.Quasi.Cooked {
            if let u = c { cooked.append(str.JSString(u)) } else { cooked.append(nil) }
        }
        for r in tt.Quasi.Raw { raw.append(str.JSString.From(r)) }
        let info = bytecode.TemplateInfo(cooked: cooked, raw: raw)
        var f: int32 = -1
        var thisReg: int32 = -1
        switch ast.StripParens(tt.Tag) {
        case .member(let mem):
            thisReg = try exprToReg(mem.Object)
            try memberGet(mem, thisReg)
            f = temp()
            emit(.star, f)
        default:
            f = try exprToReg(tt.Tag)
        }
        let first = temps(2 + tt.Quasi.Exprs.count)
        if thisReg >= 0 {
            emit(.ldar, thisReg)
        } else {
            emit(.ldaUndefined)
        }
        emit(.star, first)
        emit(.getTemplateObject, constIndex(.template(info)))
        emit(.star, first + 1)
        var i = 2
        for e in tt.Quasi.Exprs {
            try expr(e)
            emit(.star, first + int32(i))
            i += 1
        }
        emit(.callMethod, f, first, int32(1 + tt.Quasi.Exprs.count))
    }

    // MARK: generators

    /// yieldResume emits a yield of the accumulator and the dispatch on how
    /// the generator was resumed: next gives the value, throw throws it,
    /// return returns it (through finally blocks).
    func yieldValue(raw: bool) {
        let mode = temp()
        let val = temp()
        emit(.yieldOp, mode, val, raw ? 1 : 0)
        let isNext = newLabel()
        let notThrow = newLabel()
        emit(.ldar, mode)
        jump(.jumpIfFalse, isNext)
        emit(.ldaSmi, 1)
        emit(.testStrictEq, mode)
        jump(.jumpIfFalse, notThrow)
        emit(.ldar, val)
        emit(.throwOp)
        bind(notThrow)
        if isAsync {
            // An async generator awaits the value it returns.
            emit(.ldar, val)
            emit(.awaitOp)
            emit(.star, val)
        }
        unwind(to: -1, .ret(val))
        bind(isNext)
        emit(.ldar, val)
    }

    func yieldExpr(_ y: ast.YieldExpr) throws {
        let m = mark()
        defer { release(m) }
        if y.Delegate {
            try yieldStar(y.Argument!)
            return
        }
        if let a = y.Argument {
            try expr(a)
        } else {
            emit(.ldaUndefined)
        }
        if isAsync {
            emit(.awaitOp)
        }
        yieldValue(raw: false)
    }

    /// yieldStar is yield* (§15.5.5): delegate next, throw and return to
    /// the inner iterator until it is done.
    func yieldStar(_ e: ast.Expr) throws {
        try expr(e)
        let iter = temps(3)
        emit(isAsync ? .getAsyncIterator : .getIterator, iter)
        let mode = temp()
        let received = temp()
        let result = temp()
        let method = temp()
        let callArgs = temps(2)
        emit(.ldaSmi, 0)
        emit(.star, mode)
        emit(.ldaUndefined)
        emit(.star, received)
        let loop = newLabel()
        let doneL = newLabel()
        bind(loop)
        // Pick the method by mode.
        let notNext = newLabel()
        let haveResult = newLabel()
        emit(.ldar, mode)
        jump(.jumpIfTrue, notNext)
        emit(.ldar, received)
        emit(.iteratorNext, iter)
        jump(.jump, haveResult)
        bind(notNext)
        let notThrow = newLabel()
        emit(.ldaSmi, 1)
        emit(.testStrictEq, mode)
        jump(.jumpIfFalse, notThrow)
        // throw
        emit(.getNamed, iter, keyConst("throw"))
        emit(.star, method)
        let hasThrow = newLabel()
        jump(.jumpIfNotNullish, hasThrow)
        // No throw method: close the iterator, then a TypeError.
        if isAsync {
            let noRet = newLabel()
            jumpB(.asyncIteratorClose, iter, noRet)
            emit(.awaitOp)
            bind(noRet)
        } else {
            emit(.iteratorClose, iter)
        }
        throwError("The iterator does not provide a 'throw' method", 0)
        bind(hasThrow)
        emit(.ldar, iter)
        emit(.star, callArgs)
        emit(.ldar, received)
        emit(.star, callArgs + 1)
        emit(.callMethod, method, callArgs, 1)
        jump(.jump, haveResult)
        bind(notThrow)
        // return
        emit(.getNamed, iter, keyConst("return"))
        emit(.star, method)
        let hasReturn = newLabel()
        jump(.jumpIfNotNullish, hasReturn)
        emit(.ldar, received)
        if isAsync { emit(.awaitOp) }
        let rv = temp()
        emit(.star, rv)
        unwind(to: -1, .ret(rv))
        bind(hasReturn)
        emit(.ldar, iter)
        emit(.star, callArgs)
        emit(.ldar, received)
        emit(.star, callArgs + 1)
        emit(.callMethod, method, callArgs, 1)
        bind(haveResult)
        if isAsync { emit(.awaitOp) }
        emit(.star, result)
        // The result must be an object; done ends the delegation.
        emit(.ldar, result)
        let notDone = newLabel()
        let resultDone = newLabel()
        jumpB(.iteratorResult, iter, resultDone)
        // Not done: yield the inner result itself (or its value, in an
        // async generator), and resume the loop with what comes back.
        jump(.jump, notDone)
        bind(resultDone)
        emit(.getNamed, result, keyConst("value"))
        emit(.star, received)
        emit(.ldaSmi, 2)
        emit(.testStrictEq, mode)
        jump(.jumpIfFalse, doneL)
        emit(.ldar, received)
        let rv2 = temp()
        emit(.star, rv2)
        unwind(to: -1, .ret(rv2))
        bind(notDone)
        if isAsync {
            emit(.getNamed, result, keyConst("value"))
            emit(.yieldOp, mode, received, 0)
        } else {
            emit(.ldar, result)
            emit(.yieldOp, mode, received, 1)
        }
        // iteratorResult marked the record done on the way; undo that.
        emit(.ldaFalse)
        emit(.star, iter + 2)
        jump(.jump, loop)
        bind(doneL)
        emit(.ldar, received)
    }
}
