// Package scope is the static semantics of names (ECMA-262 §8.1, §9.1):
// it builds the tree of scopes, declares every binding, resolves every
// identifier, and lays the bindings out in registers and context slots.
//
// A binding a nested function refers to is "captured": it lives in a
// heap context rather than a register. So is every binding a direct eval
// or a with statement could reach by name. Names nothing declares resolve
// to the global object (or, inside with and after a sloppy direct eval,
// to a runtime lookup by name).
package scope

import "js/ast"

/// ScopeError is an early error the analysis finds (a redeclaration).
public enum ScopeError: Error, CustomStringConvertible {
    case syntax(message: string, pos: int)

    public var Message: string {
        switch self {
        case .syntax(let m, _): return m
        }
    }

    public var Pos: int {
        switch self {
        case .syntax(_, let p): return p
        }
    }

    public var description: string { return "SyntaxError: " + Message }
}

/// Mode is what kind of code is analyzed.
public enum Mode: Equatable {
    case script
    case module
    /// eval code: strict or sloppy, and whether its var scope is a
    /// function's (sloppy vars then go there at runtime).
    case eval(strict: bool)
}

/// Analyze analyzes a program and returns its top scope.
public func Analyze(_ prog: ast.Program, mode: Mode = .script) throws -> ast.Scope {
    let a = Analyzer(mode: mode)
    return try a.run(prog)
}

final class FunctionFrame {
    let node: ast.FunctionNode?
    let scope: ast.Scope
    init(node: ast.FunctionNode?, scope: ast.Scope) {
        self.node = node
        self.scope = scope
    }
}

final class Analyzer {
    let mode: Mode
    var functions: [FunctionFrame] = []
    /// evalSites are the scopes that contain a direct eval call.
    var evalSites: [ast.Scope] = []
    var top: ast.Scope? = nil
    var program: ast.Program? = nil

    init(mode: Mode) {
        self.mode = mode
    }

    func fail(_ msg: string, _ pos: int) -> ScopeError {
        return ScopeError.syntax(message: msg, pos: pos)
    }

    func run(_ prog: ast.Program) throws -> ast.Scope {
        program = prog
        var kind = ast.ScopeKind.script
        switch mode {
        case .script: kind = .script
        case .module: kind = .module
        case .eval: kind = .eval
        }
        let s = ast.Scope(kind: kind, parent: nil)
        s.Function = s
        s.Strict = prog.Strict
        if case .eval(let strict) = mode {
            s.Strict = strict || prog.Strict
        }
        top = s
        prog.Scope = s
        functions.append(FunctionFrame(node: nil, scope: s))
        // Declarations.
        try declareBody(prog.Body, s, isTop: true)
        try walkStmts(prog.Body, s)
        // Resolution: a sloppy direct eval's function is dynamic before any
        // name in it is resolved.
        markDynamicScopes()
        try resolveStmts(prog.Body, s)
        markEvalSites()
        layout(s)
        return s
    }

    // MARK: declaration

    /// isScriptTop says whether declarations here become the global
    /// object's and the global lexical environment's, not bindings.
    func isScriptTop(_ s: ast.Scope) -> bool {
        if s.Kind == .script { return true }
        if s.Kind == .eval, case .eval(let strict) = mode, !strict, !s.Strict {
            return false
        }
        return false
    }

    /// sloppyEvalTop: a sloppy eval's var and function declarations go to
    /// the caller's var scope at runtime, not to bindings here.
    func sloppyEvalTop(_ s: ast.Scope) -> bool {
        return s.Kind == .eval && !s.Strict
    }

    /// declareBody declares a function's or script's top-level lexical
    /// declarations and function declarations; vars are declared as the
    /// walk reaches them.
    func declareBody(_ body: [ast.Stmt], _ s: ast.Scope, isTop: bool) throws {
        for st in body {
            switch st {
            case .varDecl(let v) where v.Kind != .varKind:
                try declareLexicalDecl(v, s)
            case .classDecl(let c):
                try declareLexical(c.Name, .classBinding, s, c.At)
            case .functionDecl(let f):
                try declareTopFunction(f, s)
            case .exportDecl(let e):
                if let d = e.Declaration {
                    switch d {
                    case .varDecl(let v) where v.Kind != .varKind: try declareLexicalDecl(v, s)
                    case .classDecl(let c): try declareLexical(c.Name, .classBinding, s, c.At)
                    case .functionDecl(let f): try declareTopFunction(f, s)
                    default: break
                    }
                } else if e.DefaultExpr != nil {
                    _ = s.Declare("*default*", .constBinding)
                }
            case .importDecl(let im):
                for sp in im.Specifiers {
                    if s.Bindings[sp.Local] != nil {
                        throw fail("Identifier '\(sp.Local)' has already been declared", im.At)
                    }
                    let b = s.Declare(sp.Local, .constBinding)
                    b.Captured = true
                }
            default:
                break
            }
        }
    }

    func declareLexicalDecl(_ v: ast.VarDecl, _ s: ast.Scope) throws {
        var names: [string] = []
        for d in v.Declarations { ast.PatternNames(d.Target, &names) }
        for n in names {
            try declareLexical(n, v.Kind == .constKind || v.Kind.IsUsing ? .constBinding : .letBinding, s, v.At)
        }
    }

    func declareLexical(_ name: string, _ kind: ast.BindingKind, _ s: ast.Scope, _ pos: int) throws {
        if name.isEmpty { return }
        if s.Kind == .script {
            let prog = program!
            if prog.LexNames.contains(name) || prog.VarNames.contains(name) {
                throw fail("Identifier '\(name)' has already been declared", pos)
            }
            for f in prog.FunctionDecls where f.Name == name {
                throw fail("Identifier '\(name)' has already been declared", pos)
            }
            prog.LexNames.append(name)
            if kind == .constBinding || kind == .classBinding { prog.ConstNames.append(name) }
            return
        }
        if let existing = s.Bindings[name] {
            // A sloppy block may declare the same function twice (Annex B).
            if !(existing.Kind == .functionBinding && kind == .functionBinding && !s.Strict && s.Kind == .block) {
                throw fail("Identifier '\(name)' has already been declared", pos)
            }
            return
        }
        let b = s.Declare(name, kind)
        b.NeedsTDZ = kind != .functionBinding
    }

    /// declareTopFunction declares a function declaration at a function's
    /// (or script's) top level: var-like.
    func declareTopFunction(_ f: ast.FunctionNode, _ s: ast.Scope) throws {
        if s.Kind == .script {
            let prog = program!
            if prog.LexNames.contains(f.Name) {
                throw fail("Identifier '\(f.Name)' has already been declared", f.Start)
            }
            prog.FunctionDecls.append(f)
            return
        }
        if s.Kind == .module {
            if let b = s.Bindings[f.Name], b.Kind != .functionBinding {
                throw fail("Identifier '\(f.Name)' has already been declared", f.Start)
            }
            _ = s.Declare(f.Name, .functionBinding)
            return
        }
        if sloppyEvalTop(s) {
            // A sloppy eval's functions are declared where it runs.
            program!.FunctionDecls.append(f)
            return
        }
        if let b = s.Bindings[f.Name] {
            if b.IsLexical { throw fail("Identifier '\(f.Name)' has already been declared", f.Start) }
            if b.Kind == .varBinding || b.Kind == .parameter { b.Kind = .functionBinding }
            return
        }
        _ = s.Declare(f.Name, .functionBinding)
    }

    /// declareVar declares a var from scope `at` in its function's var
    /// scope, checking the scopes it passes for a lexical of the same name.
    func declareVar(_ name: string, _ at: ast.Scope, _ pos: int) throws {
        var s: ast.Scope? = at
        while let cur = s {
            if let b = cur.Bindings[name] {
                if b.IsLexical || (b.Kind == .functionBinding && cur.Kind == .block) {
                    throw fail("Identifier '\(name)' has already been declared", pos)
                }
            }
            if cur.IsFunctionBoundary {
                break
            }
            s = cur.Parent
        }
        let fs = at.Function!
        if fs.Kind == .script {
            let prog = program!
            if prog.LexNames.contains(name) {
                throw fail("Identifier '\(name)' has already been declared", pos)
            }
            if !prog.VarNames.contains(name) { prog.VarNames.append(name) }
            return
        }
        if sloppyEvalTop(fs) {
            if !program!.VarNames.contains(name) { program!.VarNames.append(name) }
            return
        }
        if fs.Bindings[name] == nil {
            _ = fs.Declare(name, .varBinding)
        }
    }

    func newScope(_ kind: ast.ScopeKind, _ parent: ast.Scope) -> ast.Scope {
        let s = ast.Scope(kind: kind, parent: parent)
        s.Function = kind == .function ? s : parent.Function
        s.Strict = parent.Strict
        return s
    }

    /// declareBlock declares a block's lexical declarations and functions.
    func declareBlock(_ body: [ast.Stmt], _ s: ast.Scope) throws {
        for st in body {
            switch st {
            case .varDecl(let v) where v.Kind != .varKind:
                try declareLexicalDecl(v, s)
            case .classDecl(let c):
                try declareLexical(c.Name, .classBinding, s, c.At)
            case .functionDecl(let f):
                try declareLexical(f.Name, .functionBinding, s, f.Start)
            default:
                break
            }
        }
        // Annex B.3.3: a sloppy block function is also a var of its function,
        // when that var would not clash with a lexical declaration.
        if !s.Strict {
            for st in body {
                if case .functionDecl(let f) = st, !f.IsAsync, !f.IsGenerator {
                    if annexBAllowed(f.Name, s) {
                        f.AnnexB = true
                        try declareVar(f.Name, s.Parent!, f.Start)
                    }
                }
            }
        }
    }

    func annexBAllowed(_ name: string, _ block: ast.Scope) -> bool {
        var s = block.Parent
        while let cur = s {
            if let b = cur.Bindings[name] {
                if b.IsLexical || (cur.Kind == .block && b.Kind == .functionBinding) {
                    return false
                }
                if cur.IsFunctionBoundary {
                    // A parameter of that name keeps its value (B.3.3.1 step 1.a.ii).
                    return b.Kind != .parameter
                }
            }
            if cur.IsFunctionBoundary { break }
            s = cur.Parent
        }
        if let prog = program, block.Function!.Kind == .script {
            if prog.LexNames.contains(name) { return false }
        }
        return true
    }

    // MARK: walking for declarations

    func walkStmts(_ body: [ast.Stmt], _ s: ast.Scope) throws {
        for st in body { try walkStmt(st, s) }
    }

    func walkStmt(_ st: ast.Stmt, _ s: ast.Scope) throws {
        switch st {
        case .varDecl(let v):
            if v.Kind == .varKind {
                var names: [string] = []
                for d in v.Declarations { ast.PatternNames(d.Target, &names) }
                for n in names { try declareVar(n, s, v.At) }
            }
            for d in v.Declarations {
                try walkPattern(d.Target, s)
                if let e = d.Init { try walkExpr(e, s) }
            }
        case .functionDecl(let f):
            try walkFunction(f, s)
        case .classDecl(let c):
            try walkClass(c, s)
        case .expr(let e):
            try walkExpr(e.Expression, s)
        case .block(let b):
            let bs = newScope(.block, s)
            b.Scope = bs
            try declareBlock(b.Body, bs)
            try walkStmts(b.Body, bs)
        case .empty, .debugger:
            break
        case .ifStmt(let i):
            try walkExpr(i.Test, s)
            try walkStmt(i.Consequent, s)
            if let a = i.Alternate { try walkStmt(a, s) }
        case .forStmt(let f):
            var ls = s
            if let initStmt = f.Init, case .varDecl(let v) = initStmt, v.Kind != .varKind {
                ls = newScope(.block, s)
                f.Scope = ls
                try declareLexicalDecl(v, ls)
            }
            if let i = f.Init { try walkStmt(i, ls) }
            if let t = f.Test { try walkExpr(t, ls) }
            if let u = f.Update { try walkExpr(u, ls) }
            try walkStmt(f.Body, ls)
        case .forIn(let f), .forOf(let f):
            // The right side sees the loop's lexical names in their TDZ.
            var ls = s
            if let d = f.Decl, d.Kind != .varKind {
                ls = newScope(.block, s)
                f.Scope = ls
                try declareLexicalDecl(d, ls)
            }
            try walkExpr(f.Right, ls)
            if let d = f.Decl {
                if d.Kind == .varKind {
                    var names: [string] = []
                    for dd in d.Declarations { ast.PatternNames(dd.Target, &names) }
                    for n in names { try declareVar(n, s, d.At) }
                }
                for dd in d.Declarations {
                    try walkPattern(dd.Target, ls)
                    if let e = dd.Init { try walkExpr(e, ls) }
                }
            }
            if let t = f.Target { try walkPattern(t, ls) }
            try walkStmt(f.Body, ls)
        case .whileStmt(let w), .doWhile(let w):
            try walkExpr(w.Test, s)
            try walkStmt(w.Body, s)
        case .returnStmt(let r):
            if let a = r.Argument { try walkExpr(a, s) }
        case .breakStmt, .continueStmt:
            break
        case .throwStmt(let t):
            try walkExpr(t.Argument, s)
        case .tryStmt(let t):
            try walkStmt(.block(t.Block), s)
            if let h = t.Handler {
                let cs = newScope(.catchClause, s)
                t.CatchScope = cs
                if let p = t.Param {
                    var names: [string] = []
                    ast.PatternNames(p, &names)
                    for n in names {
                        if cs.Bindings[n] != nil {
                            throw fail("Identifier '\(n)' has already been declared", t.At)
                        }
                        _ = cs.Declare(n, .catchParameter)
                    }
                    try walkPattern(p, cs)
                }
                // The catch body's lexicals may not redeclare the parameter.
                let bs = newScope(.block, cs)
                h.Scope = bs
                for st in h.Body {
                    var names: [string] = []
                    switch st {
                    case .varDecl(let v) where v.Kind != .varKind:
                        for d in v.Declarations { ast.PatternNames(d.Target, &names) }
                    case .classDecl(let c): names.append(c.Name)
                    case .functionDecl(let f): names.append(f.Name)
                    default: break
                    }
                    for n in names where cs.Bindings[n] != nil {
                        throw fail("Identifier '\(n)' has already been declared", t.At)
                    }
                }
                try declareBlock(h.Body, bs)
                try walkStmts(h.Body, bs)
            }
            if let f = t.Finalizer { try walkStmt(.block(f), s) }
        case .switchStmt(let sw):
            try walkExpr(sw.Discriminant, s)
            let bs = newScope(.block, s)
            sw.Scope = bs
            var all: [ast.Stmt] = []
            for c in sw.Cases { all.append(contentsOf: c.Body) }
            try declareBlock(all, bs)
            for c in sw.Cases {
                if let t = c.Test { try walkExpr(t, bs) }
                try walkStmts(c.Body, bs)
            }
        case .labeled(let l):
            try walkStmt(l.Body, s)
        case .with(let w):
            try walkExpr(w.Object, s)
            let ws = newScope(.with, s)
            w.Scope = ws
            ws.NeedsContext = true
            try walkStmt(w.Body, ws)
        case .importDecl:
            break
        case .exportDecl(let e):
            if let d = e.Declaration { try walkStmt(d, s) }
            if let x = e.DefaultExpr { try walkExpr(x, s) }
        }
    }

    func walkPattern(_ p: ast.Pattern, _ s: ast.Scope) throws {
        switch p {
        case .identifier:
            break
        case .member(let e):
            try walkExpr(e, s)
        case .array(let a):
            for el in a.Elements {
                if let e = el {
                    try walkPattern(e.Target, s)
                    if let d = e.Default { try walkExpr(d, s) }
                }
            }
            if let r = a.Rest { try walkPattern(r, s) }
        case .object(let o):
            for prop in o.Properties {
                if case .computed(let k) = prop.Key { try walkExpr(k, s) }
                try walkPattern(prop.Value.Target, s)
                if let d = prop.Value.Default { try walkExpr(d, s) }
            }
            if let r = o.Rest { try walkPattern(r, s) }
        }
    }

    func walkExprs(_ es: [ast.Expr], _ s: ast.Scope) throws {
        for e in es { try walkExpr(e, s) }
    }

    func walkExpr(_ e: ast.Expr, _ s: ast.Scope) throws {
        switch e {
        case .number, .bigint, .string, .regex, .boolean, .nullLit, .identifier, .thisExpr, .newTarget, .importMeta, .hole:
            break
        case .template(let t):
            try walkExprs(t.Exprs, s)
        case .taggedTemplate(let t):
            try walkExpr(t.Tag, s)
            try walkExprs(t.Quasi.Exprs, s)
        case .superMember(let m):
            if m.Computed { try walkExpr(m.Property, s) }
        case .superCall(let c):
            try walkExprs(c.Args, s)
        case .array(let a):
            try walkExprs(a.Elements, s)
        case .object(let o):
            for p in o.Properties {
                if case .computed(let k) = p.Key { try walkExpr(k, s) }
                try walkExpr(p.Value, s)
            }
        case .function(let f):
            try walkFunction(f, s)
        case .classExpr(let c):
            try walkClass(c, s)
        case .unary(let u):
            try walkExpr(u.Argument, s)
        case .update(let u):
            try walkExpr(u.Argument, s)
        case .binary(let b):
            try walkExpr(b.Left, s)
            try walkExpr(b.Right, s)
        case .logical(let l):
            try walkExpr(l.Left, s)
            try walkExpr(l.Right, s)
        case .assign(let a):
            try walkPattern(a.Target, s)
            try walkExpr(a.Value, s)
        case .conditional(let c):
            try walkExpr(c.Test, s)
            try walkExpr(c.Consequent, s)
            try walkExpr(c.Alternate, s)
        case .call(let c):
            try walkExpr(c.Callee, s)
            try walkExprs(c.Args, s)
            if c.DirectEval { evalSites.append(s) }
        case .newExpr(let n):
            try walkExpr(n.Callee, s)
            try walkExprs(n.Args, s)
        case .member(let m):
            try walkExpr(m.Object, s)
            if let p = m.Property { try walkExpr(p, s) }
        case .optionalChain(let o):
            try walkExpr(o.Expression, s)
        case .sequence(let q):
            try walkExprs(q.Expressions, s)
        case .spread(let sp):
            try walkExpr(sp.Argument, s)
        case .yieldExpr(let y):
            if let a = y.Argument { try walkExpr(a, s) }
        case .awaitExpr(let a):
            try walkExpr(a.Argument, s)
        case .importCall(let i):
            try walkExpr(i.Source, s)
        case .privateIn(let p):
            try walkExpr(p.Right, s)
        case .paren(let p):
            try walkExpr(p.Expression, s)
        }
    }

    func walkFunction(_ f: ast.FunctionNode, _ outer: ast.Scope) throws {
        let fs = newScope(.function, outer)
        fs.Strict = f.Strict
        f.Scope = fs
        functions.append(FunctionFrame(node: f, scope: fs))
        defer { _ = functions.removeLast() }
        // Parameters.
        for p in f.Params {
            var names: [string] = []
            ast.PatternNames(p.Target, &names)
            for n in names { _ = fs.Declare(n, .parameter) }
        }
        if let r = f.Rest {
            var names: [string] = []
            ast.PatternNames(r, &names)
            for n in names { _ = fs.Declare(n, .parameter) }
        }
        for p in f.Params {
            try walkPattern(p.Target, fs)
            if let d = p.Default { try walkExpr(d, fs) }
        }
        if let r = f.Rest { try walkPattern(r, fs) }
        if let body = f.ExprBody {
            try walkExpr(body, fs)
        } else {
            try declareBody(f.Body, fs, isTop: false)
            try walkStmts(f.Body, fs)
        }
        // A named function expression sees its own name, unless something
        // inside declares it.
        if f.IsExpression && !f.Name.isEmpty && f.Kind == .normal && fs.Bindings[f.Name] == nil {
            let b = fs.Declare(f.Name, .calleeName)
            f.SelfBinding = b
        }
    }

    func walkClass(_ c: ast.ClassNode, _ outer: ast.Scope) throws {
        let cs = newScope(.classBody, outer)
        cs.Strict = true
        c.Scope = cs
        if !c.Name.isEmpty {
            let b = cs.Declare(c.Name, .classBinding)
            b.NeedsTDZ = true
            c.NameBinding = b
        }
        for el in c.Elements {
            if case .privateName(let n) = el.Key {
                let b = cs.Bindings["#" + n] ?? cs.Declare("#" + n, .constBinding)
                el.PrivateBinding = b
            }
        }
        if let sup = c.SuperClass { try walkExpr(sup, cs) }
        if let ctor = c.Constructor { try walkFunction(ctor, cs) }
        for el in c.Elements {
            if case .computed(let k) = el.Key { try walkExpr(k, cs) }
            if let f = el.Value { try walkFunction(f, cs) }
        }
    }

    // MARK: resolution

    /// lookup resolves a name from scope s: the binding, if one is found
    /// before a dynamic boundary makes the answer a runtime lookup.
    func lookup(_ name: string, _ from: ast.Scope) -> (binding: ast.Binding?, dynamic: bool) {
        var s: ast.Scope? = from
        var crossed = false
        var dynamic = false
        while let cur = s {
            if cur.Kind == .with {
                dynamic = true
            }
            if let b = cur.Bindings[name] {
                if crossed || dynamic { b.Captured = true }
                return (b, dynamic)
            }
            if cur.Kind == .function {
                if name == "arguments", let f = functionNode(cur), !f.IsArrow, f.Kind != .classFieldInit, f.Kind != .staticBlock {
                    let b = cur.Declare("arguments", .internalBinding)
                    f.UsesArguments = true
                    f.ArgumentsBinding = b
                    if crossed || dynamic { b.Captured = true }
                    return (b, dynamic)
                }
                if cur.Dynamic { dynamic = true }
                crossed = true
            }
            if cur.Kind == .eval {
                // Eval code's free names are looked up where it runs.
                return (nil, true)
            }
            s = cur.Parent
        }
        return (nil, dynamic)
    }

    func functionNode(_ s: ast.Scope) -> ast.FunctionNode? {
        var i = functions.count - 1
        while i >= 0 {
            if functions[i].scope === s { return functions[i].node }
            i -= 1
        }
        return nil
    }

    func resolveIdentifier(_ id: ast.Identifier, _ s: ast.Scope) {
        let (b, dyn) = lookup(id.Name, s)
        id.Binding = dyn ? nil : b
        id.Dynamic = dyn
        if b != nil && b!.Kind == .varBinding && id.Name == "arguments" {
            // var arguments names the arguments object too.
            if let fs = b!.Scope, fs.Kind == .function, let f = functionNode(fs), !f.IsArrow {
                f.UsesArguments = true
                f.ArgumentsBinding = b
            }
        }
    }

    /// thisUse marks the function whose this an arrow (or eval) reaches.
    func thisUse(_ s: ast.Scope) {
        var i = functions.count - 1
        while i >= 0 {
            let fr = functions[i]
            guard let f = fr.node else { return }
            if !f.IsArrow {
                f.UsesThis = true
                return
            }
            i -= 1
        }
    }

    func inArrow() -> bool {
        guard let f = functions.last?.node else { return false }
        return f.IsArrow
    }

    func resolveStmts(_ body: [ast.Stmt], _ s: ast.Scope) throws {
        for st in body { try resolveStmt(st, s) }
    }

    func resolveStmt(_ st: ast.Stmt, _ s: ast.Scope) throws {
        switch st {
        case .varDecl(let v):
            for d in v.Declarations {
                try resolvePattern(d.Target, s)
                if let e = d.Init { try resolveExpr(e, s) }
            }
        case .functionDecl(let f):
            try resolveFunction(f)
        case .classDecl(let c):
            try resolveClass(c)
        case .expr(let e):
            try resolveExpr(e.Expression, s)
        case .block(let b):
            try resolveStmts(b.Body, b.Scope!)
        case .empty, .debugger, .breakStmt, .continueStmt, .importDecl:
            break
        case .ifStmt(let i):
            try resolveExpr(i.Test, s)
            try resolveStmt(i.Consequent, s)
            if let a = i.Alternate { try resolveStmt(a, s) }
        case .forStmt(let f):
            let ls = f.Scope ?? s
            if let i = f.Init { try resolveStmt(i, ls) }
            if let t = f.Test { try resolveExpr(t, ls) }
            if let u = f.Update { try resolveExpr(u, ls) }
            try resolveStmt(f.Body, ls)
        case .forIn(let f), .forOf(let f):
            let ls = f.Scope ?? s
            try resolveExpr(f.Right, ls)
            if let d = f.Decl {
                for dd in d.Declarations {
                    try resolvePattern(dd.Target, ls)
                    if let e = dd.Init { try resolveExpr(e, ls) }
                }
            }
            if let t = f.Target { try resolvePattern(t, ls) }
            try resolveStmt(f.Body, ls)
        case .whileStmt(let w), .doWhile(let w):
            try resolveExpr(w.Test, s)
            try resolveStmt(w.Body, s)
        case .returnStmt(let r):
            if let a = r.Argument { try resolveExpr(a, s) }
        case .throwStmt(let t):
            try resolveExpr(t.Argument, s)
        case .tryStmt(let t):
            try resolveStmt(.block(t.Block), s)
            if let h = t.Handler {
                let cs = t.CatchScope!
                if let p = t.Param { try resolvePattern(p, cs) }
                try resolveStmts(h.Body, h.Scope!)
            }
            if let f = t.Finalizer { try resolveStmt(.block(f), s) }
        case .switchStmt(let sw):
            try resolveExpr(sw.Discriminant, s)
            let bs = sw.Scope!
            for c in sw.Cases {
                if let t = c.Test { try resolveExpr(t, bs) }
                try resolveStmts(c.Body, bs)
            }
        case .labeled(let l):
            try resolveStmt(l.Body, s)
        case .with(let w):
            try resolveExpr(w.Object, s)
            try resolveStmt(w.Body, w.Scope!)
        case .exportDecl(let e):
            if let d = e.Declaration { try resolveStmt(d, s) }
            if let x = e.DefaultExpr { try resolveExpr(x, s) }
            for sp in e.Specifiers where e.Source == nil {
                let (b, _) = lookup(sp.Local, s)
                if b == nil {
                    throw fail("Export '\(sp.Local)' is not defined in module", e.At)
                }
                b!.Captured = true
            }
        }
    }

    func resolvePattern(_ p: ast.Pattern, _ s: ast.Scope) throws {
        switch p {
        case .identifier(let id):
            resolveIdentifier(id, s)
        case .member(let e):
            try resolveExpr(e, s)
        case .array(let a):
            for el in a.Elements {
                if let e = el {
                    try resolvePattern(e.Target, s)
                    if let d = e.Default { try resolveExpr(d, s) }
                }
            }
            if let r = a.Rest { try resolvePattern(r, s) }
        case .object(let o):
            for prop in o.Properties {
                if case .computed(let k) = prop.Key { try resolveExpr(k, s) }
                try resolvePattern(prop.Value.Target, s)
                if let d = prop.Value.Default { try resolveExpr(d, s) }
            }
            if let r = o.Rest { try resolvePattern(r, s) }
        }
    }

    func resolveExprs(_ es: [ast.Expr], _ s: ast.Scope) throws {
        for e in es { try resolveExpr(e, s) }
    }

    func resolveExpr(_ e: ast.Expr, _ s: ast.Scope) throws {
        switch e {
        case .number, .bigint, .string, .regex, .boolean, .nullLit, .importMeta, .hole:
            break
        case .identifier(let id):
            resolveIdentifier(id, s)
        case .thisExpr, .newTarget:
            if inArrow() { thisUse(s) }
        case .template(let t):
            try resolveExprs(t.Exprs, s)
        case .taggedTemplate(let t):
            try resolveExpr(t.Tag, s)
            try resolveExprs(t.Quasi.Exprs, s)
        case .superMember(let m):
            if inArrow() { thisUse(s) }
            if m.Computed { try resolveExpr(m.Property, s) }
        case .superCall(let c):
            if inArrow() { thisUse(s) }
            try resolveExprs(c.Args, s)
        case .array(let a):
            try resolveExprs(a.Elements, s)
        case .object(let o):
            for p in o.Properties {
                if case .computed(let k) = p.Key { try resolveExpr(k, s) }
                try resolveExpr(p.Value, s)
            }
        case .function(let f):
            try resolveFunction(f)
        case .classExpr(let c):
            try resolveClass(c)
        case .unary(let u):
            try resolveExpr(u.Argument, s)
        case .update(let u):
            try resolveExpr(u.Argument, s)
        case .binary(let b):
            try resolveExpr(b.Left, s)
            try resolveExpr(b.Right, s)
        case .logical(let l):
            try resolveExpr(l.Left, s)
            try resolveExpr(l.Right, s)
        case .assign(let a):
            try resolvePattern(a.Target, s)
            try resolveExpr(a.Value, s)
        case .conditional(let c):
            try resolveExpr(c.Test, s)
            try resolveExpr(c.Consequent, s)
            try resolveExpr(c.Alternate, s)
        case .call(let c):
            try resolveExpr(c.Callee, s)
            try resolveExprs(c.Args, s)
            if c.DirectEval {
                // eval code can use this, new.target, super and arguments.
                thisUse(s)
                _ = lookup("arguments", s)
            }
        case .newExpr(let n):
            try resolveExpr(n.Callee, s)
            try resolveExprs(n.Args, s)
        case .member(let m):
            try resolveExpr(m.Object, s)
            if let p = m.Property { try resolveExpr(p, s) }
            if m.Private {
                let (b, _) = lookup("#" + m.Name, s)
                if let pb = b { pb.Captured = pb.Captured || true }
                m.PrivateBinding = b
            }
        case .optionalChain(let o):
            try resolveExpr(o.Expression, s)
        case .sequence(let q):
            try resolveExprs(q.Expressions, s)
        case .spread(let sp):
            try resolveExpr(sp.Argument, s)
        case .yieldExpr(let y):
            if let a = y.Argument { try resolveExpr(a, s) }
        case .awaitExpr(let a):
            try resolveExpr(a.Argument, s)
        case .importCall(let i):
            try resolveExpr(i.Source, s)
        case .privateIn(let p):
            try resolveExpr(p.Right, s)
            let (b, _) = lookup("#" + p.Name, s)
            if let pb = b { pb.Captured = true }
            p.PrivateBinding = b
        case .paren(let p):
            try resolveExpr(p.Expression, s)
        }
    }

    func resolveFunction(_ f: ast.FunctionNode) throws {
        let fs = f.Scope!
        functions.append(FunctionFrame(node: f, scope: fs))
        defer { _ = functions.removeLast() }
        for p in f.Params {
            try resolvePattern(p.Target, fs)
            if let d = p.Default { try resolveExpr(d, fs) }
        }
        if let r = f.Rest { try resolvePattern(r, fs) }
        if let body = f.ExprBody {
            try resolveExpr(body, fs)
        } else {
            try resolveStmts(f.Body, fs)
        }
        // A sloppy function that uses arguments with simple parameters maps
        // them: the parameters must live in the context the object aliases.
        if f.UsesArguments && !f.Strict && f.SimpleParams && !f.IsArrow {
            for p in f.Params {
                if case .identifier(let id) = p.Target, let b = fs.Bindings[id.Name] {
                    b.Captured = true
                }
            }
        }
    }

    func resolveClass(_ c: ast.ClassNode) throws {
        let cs = c.Scope!
        // Methods reach the private names and the class's own name through
        // the class's context.
        for (_, b) in cs.Bindings where b.Name.hasPrefix("#") { b.Captured = true }
        if let sup = c.SuperClass { try resolveExpr(sup, cs) }
        if let ctor = c.Constructor { try resolveFunction(ctor) }
        for el in c.Elements {
            if case .computed(let k) = el.Key { try resolveExpr(k, cs) }
            if let f = el.Value { try resolveFunction(f) }
        }
    }

    // MARK: eval

    /// markEvalSites makes everything a direct eval could name reachable by
    /// name: every binding from the call outwards lives in a context, and a
    /// sloppy eval's function scope becomes dynamic (its vars go there).
    func markEvalSites() {
        for site in evalSites {
            var s: ast.Scope? = site
            while let cur = s {
                for b in cur.Order { b.Captured = true }
                cur.HasDirectEval = true
                s = cur.Parent
            }
        }
    }

    /// markDynamicScopes makes the function around each sloppy direct eval
    /// dynamic: the eval may declare vars there, so free names in it are
    /// looked up at runtime.
    func markDynamicScopes() {
        for site in evalSites {
            var s: ast.Scope? = site
            while let cur = s {
                if cur.Kind == .function {
                    if !cur.Strict { cur.Dynamic = true }
                    break
                }
                s = cur.Parent
            }
        }
    }

    // MARK: layout

    /// layout gives every binding its register or context slot.
    func layout(_ top: ast.Scope) {
        layoutFunction(top)
    }

    func layoutFunction(_ fs: ast.Scope) {
        var regs = 0
        layoutScope(fs, &regs)
        fs.Registers = regs
    }

    func layoutScope(_ s: ast.Scope, _ regs: inout int) {
        var slots = 0
        for b in s.Order {
            if b.Captured || s.Kind == .module || s.HasDirectEval {
                b.Captured = true
                b.Slot = slots
                slots += 1
            } else {
                b.Slot = regs
                regs += 1
            }
        }
        s.ContextSlots = slots
        // A sloppy direct eval declares its vars in the function's
        // context, so the function has one even with nothing else in it.
        if slots > 0 || (s.Kind == .function && s.Dynamic) { s.NeedsContext = true }
        for child in s.Children {
            if child.Kind == .function {
                layoutFunction(child)
            } else {
                layoutScope(child, &regs)
            }
        }
    }
}
