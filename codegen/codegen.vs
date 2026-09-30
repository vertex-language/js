// Package codegen compiles a js/ast tree, after js/scope has analyzed it,
// into js/bytecode functions.
//
// Each function is compiled by a Builder. Expressions leave their value
// in the accumulator; registers hold locals (numbered by js/scope) and
// temporaries above them. Structured control flow that leaves a scope --
// break, continue and return -- unwinds through a control stack: popping
// contexts, closing iterators, and running finally blocks, which receive
// the pending completion in a pair of registers.
package codegen

import (
    "js/ast"
    "js/bytecode"
    "js/scope"
    "js/str"
    "js/value"
)

/// CompileError is a problem found while compiling (an early error the
/// parser leaves to the compiler, or a construct not supported).
public enum CompileError: Error, CustomStringConvertible {
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

/// CompileScript compiles an analyzed script into its top-level function.
public func CompileScript(_ prog: ast.Program, source: bytecode.SourceText) throws -> bytecode.FunctionTemplate {
    let top = prog.Scope!
    let b = Builder(name: str.JSString.Empty, kind: .script, node: nil, scope: top, source: source, parent: nil)
    b.t.Strict = prog.Strict
    try b.compileProgram(prog)
    return b.finish()
}

/// CompileEval compiles eval code. A sloppy eval's vars and functions are
/// declared in the caller's var scope at runtime.
public func CompileEval(_ prog: ast.Program, source: bytecode.SourceText) throws -> bytecode.FunctionTemplate {
    let top = prog.Scope!
    let b = Builder(name: str.JSString.Empty, kind: .eval, node: nil, scope: top, source: source, parent: nil)
    b.t.Strict = top.Strict
    try b.compileProgram(prog)
    return b.finish()
}

/// Parse, analyze and compile a script in one step.
public func Compile(_ prog: ast.Program, source: bytecode.SourceText) throws -> bytecode.FunctionTemplate {
    _ = try scope.Analyze(prog)
    return try CompileScript(prog, source: source)
}

// MARK: control

public enum ControlKind: Equatable {
    case loop
    case switchBlock
    case labeled
    case finallyBlock
    case context
    case iterator
    case asyncIterator
}

/// Jump is where an unwinding jump goes once the control stack is unwound.
enum JumpAction {
    case jump(int)        // a label
    case ret(int32)       // return the value in a register
}

final class PendingJump {
    let id: int
    let target: int       // control stack index the jump stops at
    let action: JumpAction
    init(id: int, target: int, action: JumpAction) {
        self.id = id
        self.target = target
        self.action = action
    }
}

final class Control {
    let kind: ControlKind
    var labels: [string] = []
    var breakLabel: int = -1
    var continueLabel: int = -1
    // finally
    var kindReg: int32 = -1
    var valueReg: int32 = -1
    var finallyLabel: int = -1
    var pending: [PendingJump] = []
    // iterator
    var iterReg: int32 = -1

    init(kind: ControlKind) {
        self.kind = kind
    }
}

// MARK: the builder

/// Builder compiles one function.
final class Builder {
    let t: bytecode.FunctionTemplate
    let node: ast.FunctionNode?
    let fnScope: ast.Scope
    var scope: ast.Scope
    let source: bytecode.SourceText
    weak var parent: Builder?

    var nextReg: int32
    var maxReg: int32
    var labels: [int] = []
    var patches: [(label: int, at: int)] = []
    var control: [Control] = []
    /// contextDepth counts the contexts pushed in this function beyond its own.
    var contextDepth: int = 0
    var keyConsts: [string: int32] = [:]
    var strConsts: [string: int32] = [:]
    var numConsts: [uint64: int32] = [:]
    /// completion is the register holding a script's or eval's completion value.
    var completion: int32 = -1
    /// optionalExits are the labels an optional chain jumps to on null or undefined.
    var optionalExits: [int] = []
    var lastLine: int = -1
    var lineStarts: [int] = []
    /// generatorModeReg and generatorValueReg receive a resumed yield's mode and value.
    var isGenerator: bool = false
    var isAsync: bool = false
    /// disposeScopes are the registers of the dispose capabilities of the
    /// enclosing scopes that declare using, innermost last.
    var disposeScopes: [int32] = []

    init(name: str.JSString, kind: bytecode.FunctionKind, node: ast.FunctionNode?, scope: ast.Scope, source: bytecode.SourceText, parent: Builder?) {
        self.t = bytecode.FunctionTemplate(name: name, kind: kind)
        self.node = node
        self.fnScope = scope
        self.scope = scope
        self.source = source
        self.parent = parent
        self.nextReg = int32(scope.Registers)
        self.maxReg = int32(scope.Registers)
        t.Source = source
    }

    func finish() -> bytecode.FunctionTemplate {
        // Resolve label patches.
        for p in patches {
            let target = labels[p.label]
            var ins = t.Code[p.at]
            if ins.Op == .iteratorStep || ins.Op == .forInNext || ins.Op == .iteratorResult || ins.Op == .asyncIteratorClose {
                ins.B = int32(target)
            } else {
                ins.A = int32(target)
            }
            t.Code[p.at] = ins
        }
        t.RegisterCount = int(maxReg)
        return t
    }

    // MARK: emission

    @discardableResult
    func emit(_ op: bytecode.Opcode, _ a: int32 = 0, _ b: int32 = 0, _ c: int32 = 0) -> int {
        t.Code.append(bytecode.Instruction(op, a, b, c))
        return t.Code.count - 1
    }

    /// at records the source line of what is emitted next.
    func at(_ pos: int) {
        if pos < 0 { return }
        let line = lineOf(pos)
        if line != lastLine {
            t.Lines.append(t.Code.count)
            t.Lines.append(line)
            lastLine = line
        }
    }

    func lineOf(_ pos: int) -> int {
        // Build a table of line starts once.
        if lineStarts.isEmpty {
            lineStarts.append(0)
            let b = source.Bytes
            var i = 0
            while i < b.count {
                if b[i] == 0x0A { lineStarts.append(i + 1) }
                i += 1
            }
        }
        var lo = 0
        var hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= pos { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    func newLabel() -> int {
        labels.append(-1)
        return labels.count - 1
    }

    func bind(_ l: int) {
        labels[l] = t.Code.count
    }

    /// jump emits a jump (or a conditional one) to a label.
    func jump(_ op: bytecode.Opcode, _ l: int) {
        let pc = emit(op, 0)
        patches.append((label: l, at: pc))
    }

    /// jumpB emits an instruction whose B operand is a label.
    func jumpB(_ op: bytecode.Opcode, _ a: int32, _ l: int, _ c: int32 = 0) {
        let pc = emit(op, a, 0, c)
        patches.append((label: l, at: pc))
    }

    // MARK: registers

    func temp() -> int32 {
        let r = nextReg
        nextReg += 1
        if nextReg > maxReg { maxReg = nextReg }
        return r
    }

    /// temps allocates n consecutive registers.
    func temps(_ n: int) -> int32 {
        let r = nextReg
        nextReg += int32(n)
        if nextReg > maxReg { maxReg = nextReg }
        return r
    }

    func mark() -> int32 { return nextReg }

    func release(_ m: int32) { nextReg = m }

    // MARK: constants

    func constIndex(_ c: bytecode.Constant) -> int32 {
        t.Constants.append(c)
        return int32(t.Constants.count - 1)
    }

    func keyConst(_ name: string) -> int32 {
        if let i = keyConsts[name] { return i }
        let i = constIndex(.key(value.PropertyKey.Named(name)))
        keyConsts[name] = i
        return i
    }

    /// nameConst is a string constant for a name (globals, errors).
    func strConst(_ s: string) -> int32 {
        if let i = strConsts[s] { return i }
        let i = constIndex(.string(str.Name(s)))
        strConsts[s] = i
        return i
    }

    func jsStrConst(_ u: [uint16]) -> int32 {
        return constIndex(.string(str.JSString(u)))
    }

    func numConst(_ d: float64) -> int32 {
        if let i = numConsts[d.bitPattern] { return i }
        let i = constIndex(.number(d))
        numConsts[d.bitPattern] = i
        return i
    }

    func loadNumber(_ d: float64) {
        if d == d.rounded(.towardZero) && d >= -1073741824 && d <= 1073741823 && !(d == 0 && d.sign == .minus) {
            emit(.ldaSmi, int32(d))
        } else {
            emit(.ldaConst, numConst(d))
        }
    }

    func throwError(_ msg: string, _ kind: int32) {
        emit(.throwError, strConst(msg), kind)
    }

    // MARK: scopes

    /// contextHops counts the contexts between the current scope and b's.
    func contextHops(_ b: ast.Binding) -> int32 {
        var hops: int32 = 0
        var s: ast.Scope? = scope
        let target = b.Scope
        while let cur = s {
            if cur === target { return hops }
            if cur.NeedsContext { hops += 1 }
            s = cur.Parent
        }
        return hops
    }

    /// scopeInfo registers a scope's names, for runtime lookup by name.
    func scopeInfo(_ s: ast.Scope) -> int32 {
        let info = bytecode.ScopeInfo()
        info.Names = [str.JSString](repeating: str.JSString.Empty, count: s.ContextSlots)
        info.Const = [bool](repeating: false, count: s.ContextSlots)
        info.Lexical = [bool](repeating: false, count: s.ContextSlots)
        for b in s.Order where b.Captured && b.Slot >= 0 && b.Slot < s.ContextSlots {
            info.Names[b.Slot] = str.Name(b.Name)
            info.Const[b.Slot] = b.IsConst || b.Kind == .calleeName
            info.Lexical[b.Slot] = b.IsLexical
        }
        info.IsFunctionScope = s.Kind == .function || s.Kind == .eval || s.Kind == .module
        t.Scopes.append(info)
        let idx = t.Scopes.count - 1
        s.InfoIndex = idx
        return int32(idx)
    }

    /// enterScope makes s current, pushing its context if it has one, and
    /// puts its lexical bindings in their temporal dead zone.
    func enterScope(_ s: ast.Scope) {
        scope = s
        if s.NeedsContext {
            let info = scopeInfo(s)
            emit(.pushContext, int32(s.ContextSlots), info)
            contextDepth += 1
            control.append(Control(kind: .context))
        }
        for b in s.Order where !b.Captured {
            if b.IsLexical {
                emit(.ldaEmpty)
                emit(.star, int32(b.Slot))
            } else if b.Kind == .varBinding || b.Kind == .functionBinding {
                // Registers start undefined; a loop body re-entered needs no reset.
            }
        }
    }

    func exitScope(_ s: ast.Scope) {
        if s.NeedsContext {
            emit(.popContext)
            contextDepth -= 1
            _ = control.removeLast()
        }
        scope = s.Parent ?? s
    }

    // MARK: bindings

    /// loadBinding loads an identifier's value.
    func loadIdentifier(_ id: ast.Identifier, typeofOperand: bool = false) {
        if id.Name == "undefined" && id.Binding == nil && !id.Dynamic {
            emit(.ldaUndefined)
            return
        }
        if id.Dynamic {
            emit(typeofOperand ? .ldaLookupTypeof : .ldaLookup, strConst(id.Name))
            return
        }
        guard let b = id.Binding else {
            emit(typeofOperand ? .ldaGlobalTypeof : .ldaGlobal, strConst(id.Name))
            return
        }
        loadBinding(b, name: id.Name)
    }

    func loadBinding(_ b: ast.Binding, name: string) {
        if b.Captured {
            let hops = contextHops(b)
            if b.IsLexical {
                emit(.ldaCtxChecked, hops, int32(b.Slot), strConst(name))
            } else {
                emit(.ldaCtx, hops, int32(b.Slot))
            }
        } else {
            emit(.ldar, int32(b.Slot))
            if b.IsLexical {
                emit(.throwIfHole, strConst(name))
            }
        }
    }

    /// storeBinding stores the accumulator into a binding. init is set for
    /// a declaration's initialization (no TDZ or const check).
    func storeBinding(_ b: ast.Binding, name: string, initialize: bool) {
        if !initialize {
            if b.Kind == .calleeName {
                // Assigning a named function expression's own name: ignored
                // in sloppy code, an error in strict.
                if t.Strict { throwError("Assignment to constant variable.", 0) }
                return
            }
            if b.IsConst {
                // Still a ReferenceError in the TDZ.
                if b.Captured {
                    emit(.checkHoleCtx, contextHops(b), int32(b.Slot), strConst(name))
                } else {
                    emit(.checkHole, int32(b.Slot), strConst(name))
                }
                emit(.throwConstAssign, strConst(name))
                return
            }
            if b.IsLexical {
                if b.Captured {
                    emit(.checkHoleCtx, contextHops(b), int32(b.Slot), strConst(name))
                } else {
                    emit(.checkHole, int32(b.Slot), strConst(name))
                }
            }
        }
        if b.Captured {
            emit(.staCtx, contextHops(b), int32(b.Slot))
        } else {
            emit(.star, int32(b.Slot))
        }
    }

    /// storeIdentifier stores the accumulator to a name.
    func storeIdentifier(_ id: ast.Identifier, initialize: bool) {
        if id.Dynamic {
            emit(.staLookup, strConst(id.Name), t.Strict ? 1 : 0)
            return
        }
        guard let b = id.Binding else {
            if initialize && isTopLexical(id.Name) {
                emit(.initGlobalLexical, strConst(id.Name))
            } else {
                emit(.staGlobal, strConst(id.Name), t.Strict ? 1 : 0)
            }
            return
        }
        storeBinding(b, name: id.Name, initialize: initialize)
    }

    /// topLexicals are the script's let, const and class names.
    var topLexicals: [string] = []

    func isTopLexical(_ name: string) -> bool {
        var b: Builder? = self
        while let cur = b {
            if cur.topLexicals.contains(name) { return true }
            b = cur.parent
        }
        return false
    }

    // MARK: programs

    func compileProgram(_ prog: ast.Program) throws {
        let s = prog.Scope!
        topLexicals = prog.LexNames
        completion = temp()
        emit(.ldaUndefined)
        emit(.star, completion)
        if s.Kind == .script || (s.Kind == .eval && !s.Strict) {
            // GlobalDeclarationInstantiation / EvalDeclarationInstantiation.
            let decls = bytecode.GlobalDecls()
            for n in prog.VarNames { decls.VarNames.append(str.Name(n)) }
            for f in prog.FunctionDecls { decls.FunctionNames.append(str.Name(f.Name)) }
            if s.Kind == .script {
                for n in prog.LexNames { decls.LexNames.append(str.Name(n)) }
                for n in prog.ConstNames { decls.ConstNames.append(str.Name(n)) }
            }
            decls.IsEval = s.Kind == .eval
            emit(.declareGlobals, constIndex(.globals(decls)))
        }
        enterScope(s)
        if s.Kind == .eval && !s.Strict {
            // Sloppy eval: functions go to the caller's var scope.
            for f in prog.FunctionDecls {
                try compileClosure(f, nameHint: nil)
                emit(.declareEvalFunction, strConst(f.Name))
            }
        } else if s.Kind == .script {
            for f in prog.FunctionDecls {
                try compileClosure(f, nameHint: nil)
                emit(.staGlobal, strConst(f.Name), 0)
            }
        }
        try hoistFunctions(prog.Body, s, skipTop: s.Kind == .script || (s.Kind == .eval && !s.Strict))
        if let hasAwait = usingIn(prog.Body) {
            if s.Kind != .module {
                throw CompileError.syntax(message: hasAwait ? "await using declarations are not allowed at the top level of a script" : "using declarations are not allowed at the top level of a script", pos: 0)
            }
            try withDispose(hasAwait: hasAwait) {
                for st in prog.Body { try self.stmt(st) }
            }
        } else {
            for st in prog.Body {
                try stmt(st)
            }
        }
        exitScope(s)
        emit(.ldar, completion)
        emit(.returnOp)
    }

    /// hoistFunctions instantiates a scope's function declarations at its
    /// start (the declarations themselves then do nothing).
    func hoistFunctions(_ body: [ast.Stmt], _ s: ast.Scope, skipTop: bool) throws {
        if skipTop { return }
        for st in body {
            var fn: ast.FunctionNode? = nil
            if case .functionDecl(let f) = st { fn = f }
            if case .exportDecl(let e) = st, let d = e.Declaration, case .functionDecl(let f) = d { fn = f }
            guard let f = fn else { continue }
            try compileClosure(f, nameHint: nil)
            if let b = s.Bindings[f.Name] {
                storeBinding(b, name: f.Name, initialize: true)
            }
        }
    }

    /// annexBStore copies a block function's value to the function's var of
    /// the same name when its declaration is evaluated (Annex B.3.3).
    func annexBStore(_ f: ast.FunctionNode) {
        guard let blockBinding = scope.Bindings[f.Name] else { return }
        loadBinding(blockBinding, name: f.Name)
        var s: ast.Scope? = scope.Parent
        while let cur = s {
            if let b = cur.Bindings[f.Name], !b.IsLexical || cur.IsFunctionBoundary {
                if cur.IsFunctionBoundary || b.Kind == .varBinding || b.Kind == .functionBinding {
                    storeBinding(b, name: f.Name, initialize: true)
                    return
                }
            }
            if cur.IsFunctionBoundary { break }
            s = cur.Parent
        }
        // A script's var: the global object.
        emit(.staGlobal, strConst(f.Name), 0)
    }

    // MARK: functions

    /// compileClosure compiles a function node and leaves a closure of it in
    /// the accumulator.
    func compileClosure(_ f: ast.FunctionNode, nameHint: string?) throws {
        let tmpl = try compileFunction(f, nameHint: nameHint)
        emit(.createClosure, constIndex(.function(tmpl)))
    }

    func compileFunction(_ f: ast.FunctionNode, nameHint: string?) throws -> bytecode.FunctionTemplate {
        var name = f.Name
        if name.isEmpty, let h = nameHint { name = h }
        var kind = bytecode.FunctionKind.normal
        switch f.Kind {
        case .normal: kind = .normal
        case .arrow: kind = .arrow
        case .method: kind = .method
        case .getter: kind = .getter
        case .setter: kind = .setter
        case .classConstructor: kind = .classConstructor
        case .derivedConstructor: kind = .derivedConstructor
        case .classFieldInit: kind = .classFieldInit
        case .staticBlock: kind = .staticBlock
        }
        let b = Builder(name: str.JSString.From(name), kind: kind, node: f, scope: f.Scope!, source: source, parent: self)
        b.t.Strict = f.Strict
        b.t.IsAsync = f.IsAsync
        b.t.IsGenerator = f.IsGenerator
        b.isAsync = f.IsAsync
        b.isGenerator = f.IsGenerator
        b.t.Start = f.Start
        b.t.End = f.End
        b.t.Line = lineOf(f.Start)
        b.t.NeedsFunctionEnv = f.UsesThis || f.Kind == .derivedConstructor || f.Scope!.HasDirectEval
        var length = 0
        for p in f.Params {
            if p.Default != nil { break }
            length += 1
        }
        b.t.Length = length
        b.t.ParamCount = f.Params.count
        try b.compileBody(f)
        return b.finish()
    }

    /// compileBody emits the prologue (arguments, parameters, hoisted
    /// declarations) and the body.
    func compileBody(_ f: ast.FunctionNode) throws {
        let s = f.Scope!
        at(f.Start)
        if !f.SimpleParams {
            for b in s.Order where b.Kind == .parameter { b.ParamTDZ = true }
        }
        if s.NeedsContext {
            // The function's own context is made on entry by the interpreter.
            t.FunctionScope = int(scopeInfo(s))
            t.FunctionContextSlots = s.ContextSlots
        }
        scope = s
        // Lexical bindings start in their TDZ; captured ones already are.
        for b in s.Order where !b.Captured && b.IsLexical {
            emit(.ldaEmpty)
            emit(.star, int32(b.Slot))
        }
        // Captured vars start undefined.
        for b in s.Order where b.Captured && (b.Kind == .varBinding || (b.Kind == .parameter && !b.ParamTDZ)) {
            emit(.ldaUndefined)
            emit(.staCtx, 0, int32(b.Slot))
        }
        if f.UsesArguments, let ab = f.ArgumentsBinding {
            let mapped = !f.Strict && f.SimpleParams && !f.IsArrow
            if mapped {
                // Each parameter's slot in the function's context; a later
                // parameter of the same name maps instead of an earlier one.
                var slots: [int] = []
                var seen: [string] = []
                var idx = f.Params.count - 1
                var rev: [int] = []
                while idx >= 0 {
                    if case .identifier(let id) = f.Params[idx].Target, let b = s.Bindings[id.Name], b.Captured, !seen.contains(id.Name) {
                        rev.append(b.Slot)
                        seen.append(id.Name)
                    } else {
                        rev.append(-1)
                    }
                    idx -= 1
                }
                var j = rev.count - 1
                while j >= 0 { slots.append(rev[j]); j -= 1 }
                t.MappedParams = slots
            }
            emit(.createArguments, mapped ? 1 : 0)
            storeBinding(ab, name: "arguments", initialize: true)
        }
        if let sb = f.SelfBinding {
            emit(.ldaCallee)
            storeBinding(sb, name: f.Name, initialize: true)
        }
        // Parameters, left to right.
        var i = 0
        for p in f.Params {
            let m = mark()
            emit(.ldaArg, int32(i))
            if let d = p.Default {
                let skip = newLabel()
                jump(.jumpIfNotUndefined, skip)
                try exprNamed(d, patternName(p.Target))
                bind(skip)
            }
            try bindPatternFromAcc(p.Target, initialize: true)
            release(m)
            i += 1
        }
        if let r = f.Rest {
            emit(.createRest, int32(f.Params.count))
            try bindPatternFromAcc(r, initialize: true)
        }
        if f.IsGenerator {
            // The generator object is made, and the call returns, here.
            emit(.generatorStart)
        }
        if let body = f.ExprBody {
            if f.Kind == .classFieldInit {
                // An anonymous function in a field's initializer takes the field's name.
                try exprNamed(body, f.Name.isEmpty || f.Name.hasPrefix("[") ? nil : f.Name)
            } else {
                try expr(body)
            }
            emit(.returnOp)
            return
        }
        try hoistFunctions(f.Body, s, skipTop: false)
        if let hasAwait = usingIn(f.Body) {
            try withDispose(hasAwait: hasAwait) {
                for st in f.Body { try self.stmt(st) }
            }
        } else {
            for st in f.Body {
                try stmt(st)
            }
        }
        emit(.ldaUndefined)
        emit(.returnOp)
    }

    func patternName(_ p: ast.Pattern) -> string? {
        if case .identifier(let id) = p { return id.Name }
        return nil
    }
}
