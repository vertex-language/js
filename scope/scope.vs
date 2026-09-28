package scope

import "js/ast"

/// BindingKind indicates how a variable was declared.
public enum BindingKind: Equatable {
    case varKind
    case letKind
    case constKind
    case paramKind
    case functionKind
}

/// Binding describes a declared name within a scope.
public final class Binding {
    public let Name: string
    public let Kind: BindingKind
    public var Slot: int
    public var IsCaptured: bool
    public let DeclaredPos: int

    public init(name: string, kind: BindingKind, slot: int = 0, isCaptured: bool = false, declaredPos: int = 0) {
        self.Name = name
        self.Kind = kind
        self.Slot = slot
        self.IsCaptured = isCaptured
        self.DeclaredPos = declaredPos
    }
}

/// ScopeKind specifies the syntactic boundary of a scope.
public enum ScopeKind: Equatable {
    case global
    case function
    case block
    case module
}

/// Scope tracks bindings in a nested lexical environment.
public final class Scope {
    public let Kind: ScopeKind
    public weak var Parent: Scope?
    public var Children: [Scope] = []
    public var Bindings: [string: Binding] = [:]
    var nextSlot: int = 0

    public init(kind: ScopeKind, parent: Scope? = nil) {
        self.Kind = kind
        self.Parent = parent
        if kind == .block, let p = parent {
            self.nextSlot = p.nextSlot
        } else {
            self.nextSlot = 1 // slot 0 reserved for receiver 'this'
        }
    }

    /// SlotCount returns the total number of slots allocated in this scope.
    public var SlotCount: int {
        return nextSlot
    }

    /// Lookup searches this scope and all ancestors for a binding.
    public func Lookup(_ name: string) -> Binding? {
        if let b = Bindings[name] {
            return b
        }
        return Parent?.Lookup(name)
    }

    /// LookupLocal searches only this immediate scope.
    public func LookupLocal(_ name: string) -> Binding? {
        return Bindings[name]
    }

    /// LookupInCurrentFunction searches bindings up to the nearest enclosing function boundary.
    public func LookupInCurrentFunction(_ name: string) -> Binding? {
        if let b = Bindings[name] {
            return b
        }
        if Kind == .block, let p = Parent {
            return p.LookupInCurrentFunction(name)
        }
        if Kind == .global {
            return Bindings[name]
        }
        return nil
    }

    /// Declare registers a new binding in this scope.
    public func Declare(_ name: string, kind: BindingKind, pos: int = 0) -> Binding {
        if let existing = Bindings[name] {
            return existing
        }
        let b = Binding(name: name, kind: kind, slot: nextSlot, isCaptured: false, declaredPos: pos)
        nextSlot += 1
        Bindings[name] = b
        return b
    }
}

/// ScopeError describes a scoping violation like duplicate lexical declarations.
public enum ScopeError: Error, CustomStringConvertible {
    case error(message: string, pos: int)

    public var description: string {
        switch self {
        case .error(let message, let pos):
            return "ScopeError: \(message) at offset \(pos)"
        }
    }
}

/// ScopeAnalyzer computes lexical scopes and captures across an AST.
final class ScopeAnalyzer {
    let globalScope: Scope
    var currentScope: Scope

    init() {
        let g = Scope(kind: .global)
        self.globalScope = g
        self.currentScope = g
    }

    func analyze(_ program: ast.Program) throws -> Scope {
        for s in program.Body {
            try walkStmt(s)
        }
        return globalScope
    }

    func walkStmt(_ s: ast.Stmt) throws {
        switch s {
        case .block(let b):
            let blockScope = Scope(kind: .block, parent: currentScope)
            currentScope.Children.append(blockScope)
            let prev = currentScope
            currentScope = blockScope
            for item in b.Statements {
                try walkStmt(item)
            }
            if blockScope.nextSlot > prev.nextSlot {
                prev.nextSlot = blockScope.nextSlot
            }
            currentScope = prev

        case .varDecl(let v):
            let isLexical = (v.Kind == "let" || v.Kind == "const")
            let targetScope = isLexical ? currentScope : findVarScope(currentScope)
            let bKind: BindingKind = v.Kind == "let" ? .letKind : (v.Kind == "const" ? .constKind : .varKind)
            for d in v.Declarations {
                if let pat = d.Pattern {
                    let names = collectPatternNames(pat)
                    for name in names {
                        if isLexical && targetScope.LookupLocal(name) != nil {
                            throw ScopeError.error(message: "identifier '\(name)' has already been declared", pos: d.Pos)
                        }
                        _ = targetScope.Declare(name, kind: bKind, pos: d.Pos)
                    }
                    try walkPattern(pat)
                } else {
                    if isLexical && targetScope.LookupLocal(d.Id) != nil {
                        throw ScopeError.error(message: "identifier '\(d.Id)' has already been declared", pos: d.Pos)
                    }
                    _ = targetScope.Declare(d.Id, kind: bKind, pos: d.Pos)
                }
                if let initExpr = d.Init {
                    try walkExpr(initExpr)
                }
            }

        case .functionDecl(let f):
            let targetScope = findVarScope(currentScope)
            _ = targetScope.Declare(f.Name, kind: .functionKind, pos: f.Pos)
            let fnScope = Scope(kind: .function, parent: currentScope)
            currentScope.Children.append(fnScope)
            for p in f.Params {
                _ = fnScope.Declare(p, kind: .paramKind, pos: f.Pos)
            }
            if let rp = f.RestParam {
                _ = fnScope.Declare(rp, kind: .paramKind, pos: f.Pos)
            }
            let prev = currentScope
            currentScope = fnScope
            for item in f.Body.Statements {
                try walkStmt(item)
            }
            currentScope = prev

        case .classDecl(let c):
            let targetScope = currentScope
            if targetScope.LookupLocal(c.Name) != nil {
                throw ScopeError.error(message: "identifier '\(c.Name)' has already been declared", pos: c.Pos)
            }
            _ = targetScope.Declare(c.Name, kind: .letKind, pos: c.Pos)
            if let sc = c.SuperClass {
                try walkExpr(sc)
            }
            for el in c.Elements where el.Kind == .constructor {
                try walkExpr(.function(el.Value))
            }
            for el in c.Elements where el.Kind != .constructor {
                try walkExpr(.function(el.Value))
            }

        case .ifStmt(let i):
            try walkExpr(i.Test)
            try walkStmt(i.Consequent)
            if let alt = i.Alternate {
                try walkStmt(alt)
            }

        case .whileStmt(let w):
            try walkExpr(w.Test)
            try walkStmt(w.Body)

        case .doWhileStmt(let d):
            try walkStmt(d.Body)
            try walkExpr(d.Test)

        case .forStmt(let f):
            if let initStmt = f.InitStmt {
                try walkStmt(initStmt)
            } else if let initExpr = f.InitExpr {
                try walkExpr(initExpr)
            }
            if let test = f.Test { try walkExpr(test) }
            if let update = f.Update { try walkExpr(update) }
            try walkStmt(f.Body)

        case .forInStmt(let fi):
            if let lVar = fi.LeftVar {
                try walkStmt(.varDecl(lVar))
            } else if let lExpr = fi.LeftExpr {
                try walkExpr(lExpr)
            }
            try walkExpr(fi.Right)
            try walkStmt(fi.Body)

        case .forOfStmt(let fo):
            if let lVar = fo.LeftVar {
                try walkStmt(.varDecl(lVar))
            } else if let lExpr = fo.LeftExpr {
                try walkExpr(lExpr)
            }
            try walkExpr(fo.Right)
            try walkStmt(fo.Body)

        case .switchStmt(let sw):
            try walkExpr(sw.Discriminant)
            for c in sw.Cases {
                if let t = c.Test { try walkExpr(t) }
                for cs in c.Consequent {
                    try walkStmt(cs)
                }
            }

        case .returnStmt(let r):
            if let arg = r.Argument {
                try walkExpr(arg)
            }

        case .throwStmt(let t):
            try walkExpr(t.Argument)

        case .tryStmt(let tr):
            try walkStmt(.block(tr.Block))
            if let h = tr.Handler {
                let catchScope = Scope(kind: .block, parent: currentScope)
                currentScope.Children.append(catchScope)
                if let p = h.Param {
                    _ = catchScope.Declare(p, kind: .letKind, pos: h.Pos)
                }
                let prev = currentScope
                currentScope = catchScope
                for item in h.Body.Statements {
                    try walkStmt(item)
                }
                currentScope = prev
            }
            if let f = tr.Finalizer {
                try walkStmt(.block(f))
            }

        case .expr(let e):
            try walkExpr(e.Expression)

        case .breakStmt, .continueStmt, .empty:
            break
        }
    }

    func walkExpr(_ e: ast.Expr) throws {
        switch e {
        case .identifier(let id):
            if let b = currentScope.Lookup(id.Name) {
                if isCapturedFromOuterFunction(binding: b, current: currentScope) {
                    b.IsCaptured = true
                }
            }
        case .binary(let b):
            try walkExpr(b.Left)
            try walkExpr(b.Right)
        case .unary(let u):
            try walkExpr(u.Argument)
        case .assign(let a):
            try walkExpr(a.Left)
            try walkExpr(a.Right)
        case .logical(let l):
            try walkExpr(l.Left)
            try walkExpr(l.Right)
        case .conditional(let c):
            try walkExpr(c.Test)
            try walkExpr(c.Consequent)
            try walkExpr(c.Alternate)
        case .member(let m):
            try walkExpr(m.Object)
            if m.Computed {
                try walkExpr(m.Property)
            }
        case .call(let c):
            try walkExpr(c.Callee)
            for arg in c.Arguments {
                try walkExpr(arg)
            }
        case .newExpr(let n):
            try walkExpr(n.Callee)
            for arg in n.Arguments {
                try walkExpr(arg)
            }
        case .array(let a):
            for elem in a.Elements {
                if let el = elem {
                    try walkExpr(el)
                }
            }
        case .object(let o):
            for prop in o.Properties {
                if prop.Computed {
                    try walkExpr(prop.Key)
                }
                try walkExpr(prop.Value)
            }
        case .function(let f):
            let fnScope = Scope(kind: .function, parent: currentScope)
            currentScope.Children.append(fnScope)
            if let fnName = f.Id {
                _ = fnScope.Declare(fnName, kind: .functionKind, pos: f.Pos)
            }
            for p in f.Params {
                _ = fnScope.Declare(p, kind: .paramKind, pos: f.Pos)
            }
            if let rp = f.RestParam {
                _ = fnScope.Declare(rp, kind: .paramKind, pos: f.Pos)
            }
            let prev = currentScope
            currentScope = fnScope
            for item in f.Body.Statements {
                try walkStmt(item)
            }
            currentScope = prev
        case .arrow(let a):
            let arrowScope = Scope(kind: .function, parent: currentScope)
            currentScope.Children.append(arrowScope)
            for p in a.Params {
                _ = arrowScope.Declare(p, kind: .paramKind, pos: a.Pos)
            }
            if let rp = a.RestParam {
                _ = arrowScope.Declare(rp, kind: .paramKind, pos: a.Pos)
            }
            let prev = currentScope
            currentScope = arrowScope
            if let bodyStmt = a.BodyStmt {
                for item in bodyStmt.Statements {
                    try walkStmt(item)
                }
            } else if let bodyExpr = a.BodyExpr {
                try walkExpr(bodyExpr)
            }
            currentScope = prev
        case .sequence(let seq):
            for ex in seq.Expressions {
                try walkExpr(ex)
            }
        case .template(let t):
            for ex in t.Expressions {
                try walkExpr(ex)
            }
        case .spread(let s):
            try walkExpr(s.Argument)
        case .classExpr(let c):
            if let sc = c.SuperClass {
                try walkExpr(sc)
            }
            for el in c.Elements where el.Kind == .constructor {
                try walkExpr(.function(el.Value))
            }
            for el in c.Elements where el.Kind != .constructor {
                try walkExpr(.function(el.Value))
            }
        case .pattern(let p):
            try walkPattern(p)
        case .awaitExpr(let a):
            try walkExpr(a.Argument)
        case .yieldExpr(let y):
            if let arg = y.Argument {
                try walkExpr(arg)
            }
        case .number, .string, .boolean, .nullLit, .undefinedLit, .thisExpr, .superExpr:
            break
        }
    }

    func collectBindingNames(_ target: ast.DestructureTarget) -> [string] {
        switch target {
        case .identifier(let name):
            return [name]
        case .member:
            return []
        case .pattern(let p):
            return collectPatternNames(p)
        }
    }

    func collectPatternNames(_ p: ast.BindingPattern) -> [string] {
        var names: [string] = []
        switch p {
        case .array(let arr):
            for el in arr.Elements {
                if let t = el.Target {
                    names.append(contentsOf: collectBindingNames(t))
                }
            }
        case .object(let obj):
            for prop in obj.Properties {
                names.append(contentsOf: collectBindingNames(prop.Target))
            }
        }
        return names
    }

    func walkDestructureTarget(_ target: ast.DestructureTarget) throws {
        switch target {
        case .identifier(let name):
            if let b = currentScope.Lookup(name) {
                if isCapturedFromOuterFunction(binding: b, current: currentScope) {
                    b.IsCaptured = true
                }
            }
        case .member(let m):
            try walkExpr(m.Object)
            if m.Computed {
                try walkExpr(m.Property)
            }
        case .pattern(let p):
            try walkPattern(p)
        }
    }

    func walkPattern(_ p: ast.BindingPattern) throws {
        switch p {
        case .array(let arr):
            for el in arr.Elements {
                if let def = el.DefaultValue {
                    try walkExpr(def)
                }
                if let t = el.Target {
                    try walkDestructureTarget(t)
                }
            }
        case .object(let obj):
            for prop in obj.Properties {
                if let comp = prop.ComputedKey {
                    try walkExpr(comp)
                }
                if let def = prop.DefaultValue {
                    try walkExpr(def)
                }
                try walkDestructureTarget(prop.Target)
            }
        }
    }

    func findVarScope(_ s: Scope) -> Scope {
        var cur: Scope? = s
        while let c = cur {
            if c.Kind == .function || c.Kind == .global || c.Kind == .module {
                return c
            }
            cur = c.Parent
        }
        return s
    }

    func isCapturedFromOuterFunction(binding: Binding, current: Scope) -> bool {
        var cur: Scope? = current
        var crossedFunction = false
        while let c = cur {
            if c.Bindings[binding.Name] != nil {
                return crossedFunction
            }
            if c.Kind == .function {
                crossedFunction = true
            }
            cur = c.Parent
        }
        return false
    }
}

/// Analyze walks a Program AST and computes lexical scopes and bindings.
public func Analyze(_ program: ast.Program) throws -> Scope {
    let analyzer = ScopeAnalyzer()
    return try analyzer.analyze(program)
}
