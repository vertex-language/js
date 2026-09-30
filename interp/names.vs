package interp

import (
    "js/bytecode"
    "js/codegen"
    "js/object"
    "js/parser"
    "js/scope"
    "js/str"
    "js/value"
)

extension Engine {
    // MARK: globals

    func notDefined(_ name: str.JSString) -> object.Completion {
        return object.ThrowReferenceError("\(name.String) is not defined")
    }

    /// loadGlobal reads a name from the global lexical environment, then
    /// the global object.
    func loadGlobal(_ r: object.Realm, _ name: str.JSString, typeofOperand: bool) throws -> Value {
        if let b = r.GlobalLexicals[name] {
            if b.Value.IsEmpty {
                throw object.ThrowReferenceError("Cannot access '\(name.String)' before initialization")
            }
            return b.Value
        }
        let key = value.PropertyKey.FromString(name)
        let g = r.Global
        let i = g.find(key)
        if i >= 0, let slot = g.OwnSlot(key), !slot.IsAccessor {
            return slot.Value
        }
        if try g.HasProperty(key) {
            return try g.Get(key, .object(g))
        }
        if typeofOperand { return .undefined }
        throw notDefined(name)
    }

    func storeGlobal(_ r: object.Realm, _ name: str.JSString, _ v: Value, strict: bool) throws {
        if let b = r.GlobalLexicals[name] {
            if b.Value.IsEmpty {
                throw object.ThrowReferenceError("Cannot access '\(name.String)' before initialization")
            }
            if b.IsConst {
                throw object.ThrowTypeError("Assignment to constant variable.")
            }
            b.Value = v
            return
        }
        let key = value.PropertyKey.FromString(name)
        let g = r.Global
        if strict && !(try g.HasProperty(key)) {
            throw notDefined(name)
        }
        let ok = try g.Set(key, v, .object(g))
        if !ok && strict {
            throw object.ThrowTypeError("Cannot assign to read only property '\(name.String)' of object '#<Object>'")
        }
    }

    /// declareGlobals is GlobalDeclarationInstantiation (§16.1.7), and
    /// EvalDeclarationInstantiation's var part for a sloppy eval.
    func declareGlobals(_ f: Frame, _ d: bytecode.GlobalDecls) throws {
        let r = f.realm
        let g = r.Global
        if d.IsEval {
            // A sloppy eval declares its vars where its caller's vars are.
            for n in d.VarNames { try declareEvalVar(f, n, .undefined, assign: false) }
            for n in d.FunctionNames { try declareEvalVar(f, n, .undefined, assign: false) }
            return
        }
        for n in d.LexNames {
            if r.GlobalLexicals[n] != nil {
                throw object.ThrowSyntaxError("Identifier '\(n.String)' has already been declared")
            }
            let key = value.PropertyKey.FromString(n)
            if let desc = try g.GetOwnProperty(key), desc.Configurable == false {
                throw object.ThrowSyntaxError("Identifier '\(n.String)' has already been declared")
            }
        }
        for n in d.VarNames {
            if r.GlobalLexicals[n] != nil {
                throw object.ThrowSyntaxError("Identifier '\(n.String)' has already been declared")
            }
        }
        for n in d.FunctionNames {
            if r.GlobalLexicals[n] != nil {
                throw object.ThrowSyntaxError("Identifier '\(n.String)' has already been declared")
            }
        }
        for n in d.FunctionNames {
            let key = value.PropertyKey.FromString(n)
            let existing = try g.GetOwnProperty(key)
            if existing == nil || existing!.Configurable == true {
                try object.DefinePropertyOrThrow(g, key, object.PropertyDescriptor.Data(.undefined, writable: true, enumerable: true, configurable: false))
            }
        }
        for n in d.VarNames {
            let key = value.PropertyKey.FromString(n)
            if try g.GetOwnProperty(key) == nil && (try g.IsExtensibleObject()) {
                try object.DefinePropertyOrThrow(g, key, object.PropertyDescriptor.Data(.undefined, writable: true, enumerable: true, configurable: false))
            }
        }
        var i = 0
        for n in d.LexNames {
            let isConst = d.ConstNames.contains(where: { $0.Equals(n) })
            r.GlobalLexicals[n] = object.GlobalBinding(value: .empty, isConst: isConst)
            i += 1
        }
    }

    // MARK: lookup by name

    /// lookupName resolves a name at runtime (inside with, or after a
    /// sloppy direct eval): contexts outwards, then the globals.
    func lookupName(_ f: Frame, _ name: str.JSString, typeofOperand: bool) throws -> Value {
        let (v, _) = try lookup(f, name, typeofOperand: typeofOperand)
        return v
    }

    func lookupNameWithThis(_ f: Frame, _ name: str.JSString) throws -> (Value, Value) {
        return try lookup(f, name, typeofOperand: false)
    }

    func lookup(_ f: Frame, _ name: str.JSString, typeofOperand: bool) throws -> (Value, Value) {
        let key = value.PropertyKey.FromString(name)
        var c = f.ctx
        while let ctx = c {
            if let w = ctx.WithObject {
                if try w.HasProperty(key), !(try unscopable(w, key)) {
                    return (try w.Get(key, .object(w)), .object(w))
                }
            } else {
                if let info = ctx.Info {
                    let i = info.Find(name)
                    if i >= 0 {
                        let v = ctx.Slots[i]
                        if v.IsEmpty {
                            throw object.ThrowReferenceError("Cannot access '\(name.String)' before initialization")
                        }
                        return (v, .undefined)
                    }
                }
                if let ext = ctx.Extension, ext.find(key) >= 0 {
                    return (try ext.Get(key, .object(ext)), .undefined)
                }
            }
            c = ctx.Parent
        }
        return (try loadGlobal(f.realm, name, typeofOperand: typeofOperand), .undefined)
    }

    func unscopable(_ o: object.JSObject, _ key: value.PropertyKey) throws -> bool {
        let u = try o.Get(.symbol(value.SymUnscopables), .object(o))
        if case .object(let uo) = u {
            return try uo.Get(key, u).Truthy
        }
        return false
    }

    func storeName(_ f: Frame, _ name: str.JSString, _ v: Value, strict: bool) throws {
        let key = value.PropertyKey.FromString(name)
        var c = f.ctx
        while let ctx = c {
            if let w = ctx.WithObject {
                if try w.HasProperty(key), !(try unscopable(w, key)) {
                    let ok = try w.Set(key, v, .object(w))
                    if !ok && strict {
                        throw object.ThrowTypeError("Cannot assign to read only property '\(name.String)' of object")
                    }
                    return
                }
            } else {
                if let info = ctx.Info {
                    let i = info.Find(name)
                    if i >= 0 {
                        if ctx.Slots[i].IsEmpty && info.Lexical[i] {
                            throw object.ThrowReferenceError("Cannot access '\(name.String)' before initialization")
                        }
                        if info.Const[i] {
                            if info.Lexical[i] || strict {
                                throw object.ThrowTypeError("Assignment to constant variable.")
                            }
                            return
                        }
                        ctx.Slots[i] = v
                        return
                    }
                }
                if let ext = ctx.Extension, ext.find(key) >= 0 {
                    _ = try ext.Set(key, v, .object(ext))
                    return
                }
            }
            c = ctx.Parent
        }
        try storeGlobal(f.realm, name, v, strict: strict)
    }

    func deleteName(_ f: Frame, _ name: str.JSString) throws -> bool {
        let key = value.PropertyKey.FromString(name)
        var c = f.ctx
        while let ctx = c {
            if let w = ctx.WithObject {
                if try w.HasProperty(key) { return try w.Delete(key) }
            } else {
                if let info = ctx.Info, info.Find(name) >= 0 { return false }
                if let ext = ctx.Extension, ext.find(key) >= 0 { return try ext.Delete(key) }
            }
            c = ctx.Parent
        }
        let r = f.realm
        if r.GlobalLexicals[name] != nil { return false }
        return try r.Global.Delete(key)
    }

    /// declareEvalVar puts a sloppy eval's var (or function) in its
    /// caller's var scope: a function context's extension, or the global object.
    func declareEvalVar(_ f: Frame, _ name: str.JSString, _ v: Value, assign: bool) throws {
        let key = value.PropertyKey.FromString(name)
        if let vc = f.varContext {
            if let info = vc.Info {
                let i = info.Find(name)
                if i >= 0 {
                    if assign { vc.Slots[i] = v }
                    return
                }
            }
            if vc.Extension == nil { vc.Extension = object.JSObject(proto: nil) }
            let ext = vc.Extension!
            if ext.find(key) < 0 {
                ext.DefineData(key, .undefined)
            }
            if assign { ext.DefineData(key, v) }
            return
        }
        let g = f.realm.Global
        if f.realm.GlobalLexicals[name] != nil {
            throw object.ThrowSyntaxError("Identifier '\(name.String)' has already been declared")
        }
        if try g.GetOwnProperty(key) == nil {
            try object.DefinePropertyOrThrow(g, key, object.PropertyDescriptor.Data(.undefined, writable: true, enumerable: true, configurable: true))
        }
        if assign {
            _ = try g.Set(key, v, .object(g))
        }
    }

    // MARK: eval

    func callEval(_ f: Frame, _ callee: Value, _ args: [Value]) throws -> Value {
        guard case .object(let o) = callee, let ev = f.realm.EvalFunction, o === ev else {
            return try callValue(f, callee, .undefined, args)
        }
        guard args.count > 0, case .string(let src) = args[0] else {
            return args.count > 0 ? args[0] : .undefined
        }
        return try directEval(f, src)
    }

    /// compileEval parses, analyzes and compiles eval code.
    func compileEval(_ src: str.JSString, strict: bool, inFunction: bool, allowSuper: bool, allowNewTarget: bool) throws -> bytecode.FunctionTemplate {
        var opts = parser.Options()
        opts.Strict = strict
        opts.InFunction = inFunction
        opts.AllowNewTarget = allowNewTarget
        opts.AllowSuperProperty = allowSuper
        let text = src.String
        do {
            let prog = try parser.Parse(text, filename: "eval", options: opts)
            let isStrict = strict || prog.Strict
            _ = try scope.Analyze(prog, mode: .eval(strict: isStrict))
            return try codegen.CompileEval(prog, source: bytecode.SourceText(filename: "<eval>", text: text))
        } catch let e as parser.ParseError {
            throw object.ThrowSyntaxError(e.Message)
        } catch let e as scope.ScopeError {
            throw object.ThrowSyntaxError(e.Message)
        } catch let e as codegen.CompileError {
            throw object.ThrowSyntaxError(e.Message)
        }
    }

    func directEval(_ f: Frame, _ src: str.JSString) throws -> Value {
        let inFunction = f.fn != nil
        var allowSuper = false
        if let fn = activeFunction(f), fn.HomeObject != nil { allowSuper = true }
        let t = try compileEval(src, strict: f.t.Strict, inFunction: inFunction, allowSuper: allowSuper, allowNewTarget: inFunction)
        let ef = Frame(t: t, fn: f.fn, args: f.args, this: f.this, newTarget: f.newTarget, ctx: f.ctx, realm: f.realm)
        ef.isEval = true
        ef.funcEnv = f.funcEnv
        if let fe = f.funcEnv {
            ef.this = fe.This
            ef.newTarget = fe.NewTarget
        }
        // A sloppy eval's vars go to the innermost function context.
        var c = f.ctx
        while let ctx = c {
            if let info = ctx.Info, info.IsFunctionScope { break }
            c = ctx.Parent
        }
        ef.varContext = inFunction ? c : nil
        return try complete(ef)
    }

    public func IndirectEval(_ realm: object.Realm, _ src: str.JSString) throws -> Value {
        let t = try compileEval(src, strict: false, inFunction: false, allowSuper: false, allowNewTarget: false)
        let ef = Frame(t: t, fn: nil, args: [], this: .object(realm.Global), newTarget: .undefined, ctx: nil, realm: realm)
        ef.isEval = true
        return try complete(ef)
    }

    // MARK: new Function

    public func CreateDynamicFunction(_ realm: object.Realm, _ args: [Value], _ newTarget: object.JSObject?, isAsync: bool, isGenerator: bool) throws -> object.JSObject {
        var params = ""
        var body = ""
        if args.count > 0 {
            var i = 0
            while i < args.count - 1 {
                if i > 0 { params += "," }
                params += try object.ToString(args[i]).String
                i += 1
            }
            body = try object.ToString(args[args.count - 1]).String
        }
        do {
            _ = try parser.ParseFunctionParts(params: params, body: body, isAsync: isAsync, isGenerator: isGenerator)
        } catch let e as parser.ParseError {
            throw object.ThrowSyntaxError(e.Message)
        }
        let kw = isAsync ? (isGenerator ? "async function*" : "async function") : (isGenerator ? "function*" : "function")
        let text = "(\(kw) anonymous(\(params)\n) {\n\(body)\n})"
        let t: bytecode.FunctionTemplate
        do {
            let prog = try parser.ParseScript(text, filename: "anonymous")
            _ = try scope.Analyze(prog)
            t = try codegen.CompileScript(prog, source: bytecode.SourceText(filename: "<anonymous>", text: text))
        } catch let e as parser.ParseError {
            throw object.ThrowSyntaxError(e.Message)
        } catch let e as scope.ScopeError {
            throw object.ThrowSyntaxError(e.Message)
        }
        let f = Frame(t: t, fn: nil, args: [], this: .object(realm.Global), newTarget: .undefined, ctx: nil, realm: realm)
        let v = try complete(f)
        guard case .object(let fn) = v else { throw object.ThrowSyntaxError("Invalid function") }
        // The function's text is the synthesized source, without the parentheses.
        if let jf = fn as? object.JSFunction {
            jf.Template.Start = 1
            jf.Template.End = text.utf8.count - 1
            if let nt = newTarget {
                var fallback = realm.FunctionPrototype
                if isAsync && isGenerator { fallback = realm.AsyncGeneratorFunctionPrototype } else if isGenerator { fallback = realm.GeneratorFunctionPrototype } else if isAsync { fallback = realm.AsyncFunctionPrototype }
                jf.Proto = try object.GetPrototypeFromConstructor(nt, fallback)
            }
        }
        return fn
    }
}
