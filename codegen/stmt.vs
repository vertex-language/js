package codegen

import (
    "js/ast"
    "js/bytecode"
)

func stmtPos(_ s: ast.Stmt) -> int {
    switch s {
    case .varDecl(let v): return v.At
    case .functionDecl(let f): return f.Start
    case .classDecl(let c): return c.At
    case .expr(let e): return e.At
    case .block(let b): return b.At
    case .empty(let p): return p.At
    case .ifStmt(let i): return i.At
    case .forStmt(let f): return f.At
    case .forIn(let f): return f.At
    case .forOf(let f): return f.At
    case .whileStmt(let w): return w.At
    case .doWhile(let w): return w.At
    case .returnStmt(let r): return r.At
    case .breakStmt(let j): return j.At
    case .continueStmt(let j): return j.At
    case .throwStmt(let t): return t.At
    case .tryStmt(let t): return t.At
    case .switchStmt(let s): return s.At
    case .labeled(let l): return l.At
    case .with(let w): return w.At
    case .debugger(let p): return p.At
    case .importDecl(let i): return i.At
    case .exportDecl(let e): return e.At
    }
}

extension Builder {
    func stmt(_ s: ast.Stmt) throws {
        at(stmtPos(s))
        let m = mark()
        defer { release(m) }
        switch s {
        case .empty, .debugger, .importDecl:
            break
        case .expr(let e):
            try expr(e.Expression)
            if completion >= 0 { emit(.star, completion) }
        case .varDecl(let v):
            try varDecl(v)
        case .functionDecl(let f):
            // Hoisted; Annex B copies a block function out when evaluated.
            if f.AnnexB { annexBStore(f) }
        case .classDecl(let c):
            try classDef(c, nameHint: nil)
            if let b = scope.Bindings[c.Name] {
                storeBinding(b, name: c.Name, initialize: true)
            } else {
                emit(.initGlobalLexical, strConst(c.Name))
            }
        case .block(let b):
            try block(b)
        case .ifStmt(let i):
            let elseL = newLabel()
            let endL = newLabel()
            try condition(i.Test, falseLabel: elseL)
            try stmt(i.Consequent)
            if let a = i.Alternate {
                jump(.jump, endL)
                bind(elseL)
                try stmt(a)
            } else {
                bind(elseL)
            }
            bind(endL)
        case .whileStmt(let w):
            let top = newLabel()
            let end = newLabel()
            let c = pushLoop(w.Labels, breakL: end, continueL: top)
            bind(top)
            try condition(w.Test, falseLabel: end)
            try stmt(w.Body)
            jump(.jump, top)
            bind(end)
            popControl(c)
        case .doWhile(let w):
            let top = newLabel()
            let cont = newLabel()
            let end = newLabel()
            let c = pushLoop(w.Labels, breakL: end, continueL: cont)
            bind(top)
            try stmt(w.Body)
            bind(cont)
            try expr(w.Test)
            jump(.jumpIfTrue, top)
            bind(end)
            popControl(c)
        case .forStmt(let f):
            try forStmt(f)
        case .forIn(let f):
            try forIn(f)
        case .forOf(let f):
            try forOf(f)
        case .returnStmt(let r):
            if let a = r.Argument {
                try expr(a)
                if isAsync && isGenerator {
                    emit(.awaitOp)
                }
            } else {
                emit(.ldaUndefined)
            }
            let v = temp()
            emit(.star, v)
            unwind(to: -1, .ret(v))
        case .breakStmt(let j):
            let target = findBreak(j.Label)
            unwind(to: target, .jump(control[target].breakLabel))
        case .continueStmt(let j):
            let target = findContinue(j.Label)
            unwind(to: target, .jump(control[target].continueLabel))
        case .throwStmt(let tr):
            try expr(tr.Argument)
            emit(.throwOp)
        case .tryStmt(let tr):
            try tryStmt(tr)
        case .switchStmt(let sw):
            try switchStmt(sw)
        case .labeled(let l):
            // Loops and switches take their labels themselves; any other
            // statement gets a break target of its own.
            switch l.Body {
            case .forStmt, .forIn, .forOf, .whileStmt, .doWhile, .switchStmt, .labeled:
                try stmt(l.Body)
            default:
                let end = newLabel()
                let c = Control(kind: .labeled)
                c.labels = [l.Label]
                c.breakLabel = end
                control.append(c)
                try stmt(l.Body)
                popControl(c)
                bind(end)
            }
        case .with(let w):
            try expr(w.Object)
            let ws = w.Scope!
            // The with context holds the object (ToObject'd by the interpreter).
            scope = ws
            emit(.pushContext, -1, scopeInfo(ws))
            contextDepth += 1
            control.append(Control(kind: .context))
            try stmt(w.Body)
            exitScope(ws)
        case .exportDecl(let e):
            try exportDecl(e)
        }
    }

    func block(_ b: ast.BlockStmt) throws {
        let s = b.Scope!
        enterScope(s)
        try hoistFunctions(b.Body, s, skipTop: false)
        if let hasAwait = usingIn(b.Body) {
            try withDispose(hasAwait: hasAwait) {
                for st in b.Body { try self.stmt(st) }
            }
        } else {
            for st in b.Body { try stmt(st) }
        }
        exitScope(s)
    }

    // MARK: using (explicit resource management, ES2026)

    /// usingIn says whether a statement list declares using directly: nil
    /// if not, else whether any is an await using.
    func usingIn(_ body: [ast.Stmt]) -> bool? {
        var found = false
        var hasAwait = false
        for st in body {
            if case .varDecl(let v) = st, v.Kind.IsUsing {
                found = true
                if v.Kind == .awaitUsingKind { hasAwait = true }
            }
        }
        return found ? hasAwait : nil
    }

    /// withDispose compiles body with a dispose capability: its using
    /// declarations add resources, and however the body completes -- normally,
    /// by throw, return, break or continue -- the resources are disposed,
    /// newest first (DisposeResources, §9.4.5 of ES2026), before the
    /// completion goes on. A dispose error replaces the completion, a
    /// later one wrapping an earlier as a SuppressedError.
    func withDispose(hasAwait: bool, _ body: () throws -> Void) throws {
        let scopeReg = temp()
        emit(.createDisposeScope, scopeReg)
        let f = Control(kind: .finallyBlock)
        f.kindReg = temp()
        f.valueReg = temp()
        let finallyL = newLabel()
        f.finallyLabel = finallyL
        control.append(f)
        disposeScopes.append(scopeReg)
        let depth = contextDepth
        let tryStart = t.Code.count
        try body()
        let tryEnd = t.Code.count
        disposeScopes.removeLast()
        emit(.ldaSmi, 0)
        emit(.star, f.kindReg)
        jump(.jump, finallyL)
        popControl(f)
        let throwPad = t.Code.count
        emit(.star, f.valueReg)
        emit(.ldaSmi, 1)
        emit(.star, f.kindReg)
        bind(finallyL)
        t.Handlers.append(bytecode.Handler(start: tryStart, end: tryEnd, target: throwPad, isFinally: true, kindReg: int(f.kindReg), valueReg: int(f.valueReg), finallyStart: labels[finallyL], contextDepth: depth))
        // A throw from the body is the completion disposal starts from.
        let notThrown = newLabel()
        emit(.ldaSmi, 1)
        emit(.testStrictEq, f.kindReg)
        jump(.jumpIfFalse, notThrown)
        emit(.ldar, f.valueReg)
        emit(.disposeError, scopeReg)
        bind(notThrown)
        let loop = newLabel()
        let done = newLabel()
        let out = temp()
        bind(loop)
        emit(.disposeNext, scopeReg, out)
        jump(.jumpIfFalse, done)
        if hasAwait {
            let status = temp()
            emit(.star, status)
            emit(.ldaSmi, 2)
            emit(.testStrictEq, status)
            jump(.jumpIfFalse, loop)
            let awaitStart = t.Code.count
            emit(.ldar, out)
            emit(.awaitOp)
            let awaitEnd = t.Code.count
            jump(.jump, loop)
            let pad = t.Code.count
            emit(.disposeError, scopeReg)
            jump(.jump, loop)
            t.Handlers.append(bytecode.Handler(start: awaitStart, end: awaitEnd, target: pad, isFinally: false, contextDepth: contextDepth))
        } else {
            jump(.jump, loop)
        }
        bind(done)
        emit(.disposeFinish, scopeReg)
        // Go on with the completion, as a finally block does.
        let normal = newLabel()
        emit(.ldar, f.kindReg)
        jump(.jumpIfFalse, normal)
        let notThrow = newLabel()
        emit(.ldaSmi, 1)
        emit(.testStrictEq, f.kindReg)
        jump(.jumpIfFalse, notThrow)
        emit(.ldar, f.valueReg)
        emit(.throwOp)
        bind(notThrow)
        let notReturn = newLabel()
        emit(.ldaSmi, 2)
        emit(.testStrictEq, f.kindReg)
        jump(.jumpIfFalse, notReturn)
        unwind(to: -1, .ret(f.valueReg))
        bind(notReturn)
        for p in f.pending {
            let next = newLabel()
            emit(.ldaSmi, int32(p.id))
            emit(.testStrictEq, f.kindReg)
            jump(.jumpIfFalse, next)
            unwind(to: p.target, p.action)
            bind(next)
        }
        bind(normal)
    }

    func varDecl(_ v: ast.VarDecl) throws {
        for d in v.Declarations {
            if let e = d.Init {
                try exprNamed(e, patternName(d.Target))
                if v.Kind.IsUsing, let reg = disposeScopes.last {
                    // The resource is added once its binding is initialized.
                    let m = mark()
                    let val = temp()
                    emit(.star, val)
                    try bindPatternFromAcc(d.Target, initialize: true)
                    emit(.ldar, val)
                    emit(.addDisposable, reg, v.Kind == .awaitUsingKind ? 1 : 0)
                    release(m)
                    continue
                }
                try bindPatternFromAcc(d.Target, initialize: v.Kind != .varKind)
            } else if v.Kind != .varKind {
                // let x; is x = undefined.
                emit(.ldaUndefined)
                try bindPatternFromAcc(d.Target, initialize: true)
            }
        }
    }

    // MARK: conditions

    /// condition jumps to falseLabel when e is falsy, testing logical
    /// operators without materializing their value.
    func condition(_ e: ast.Expr, falseLabel: int) throws {
        switch ast.StripParens(e) {
        case .logical(let l) where l.Op == .logicalAnd:
            try condition(l.Left, falseLabel: falseLabel)
            try condition(l.Right, falseLabel: falseLabel)
        case .unary(let u) where u.Op == .logicalNot:
            // if (!x): x being true is the false branch.
            try conditionTrue(u.Argument, trueLabel: falseLabel)
        default:
            try expr(e)
            jump(.jumpIfFalse, falseLabel)
        }
    }

    func conditionTrue(_ e: ast.Expr, trueLabel: int) throws {
        try expr(e)
        jump(.jumpIfTrue, trueLabel)
    }

    // MARK: the control stack

    func pushLoop(_ labels: [string], breakL: int, continueL: int) -> Control {
        let c = Control(kind: .loop)
        c.labels = labels
        c.breakLabel = breakL
        c.continueLabel = continueL
        control.append(c)
        return c
    }

    func popControl(_ c: Control) {
        if let i = control.lastIndex(where: { $0 === c }) {
            control.remove(at: i)
        }
    }

    func findBreak(_ label: string?) -> int {
        var i = control.count - 1
        while i >= 0 {
            let c = control[i]
            if let l = label {
                if c.labels.contains(l) && c.breakLabel >= 0 { return i }
            } else if (c.kind == .loop || c.kind == .switchBlock) && c.breakLabel >= 0 {
                return i
            }
            i -= 1
        }
        return 0
    }

    func findContinue(_ label: string?) -> int {
        var i = control.count - 1
        while i >= 0 {
            let c = control[i]
            if c.kind == .loop && c.continueLabel >= 0 {
                if label == nil || c.labels.contains(label!) { return i }
            }
            i -= 1
        }
        return 0
    }

    /// unwind leaves every control entry above `target` (-1: the whole
    /// function) and then performs the action. A finally block on the way
    /// takes the jump over: its dispatch continues the unwinding later.
    func unwind(to target: int, _ action: JumpAction) {
        var i = control.count - 1
        while i > target {
            let c = control[i]
            switch c.kind {
            case .context:
                emit(.popContext)
            case .iterator:
                emit(.iteratorClose, c.iterReg)
            case .asyncIterator:
                // for await: close with an awaited return.
                let noReturn = newLabel()
                jumpB(.asyncIteratorClose, c.iterReg, noReturn)
                emit(.awaitOp)
                bind(noReturn)
            case .finallyBlock:
                // A return saves its value in the finally's value register
                // (kind 2): the finally body may reuse the temp holding it.
                var id: int = 2
                if case .ret(let r) = action {
                    emit(.ldar, r)
                    emit(.star, c.valueReg)
                } else {
                    id = 3 + c.pending.count
                    c.pending.append(PendingJump(id: id, target: target, action: action))
                }
                emit(.ldaSmi, int32(id))
                emit(.star, c.kindReg)
                jump(.jump, c.finallyLabel)
                return
            default:
                break
            }
            i -= 1
        }
        switch action {
        case .jump(let l):
            jump(.jump, l)
        case .ret(let r):
            emit(.ldar, r)
            emit(.returnOp)
        }
    }

    // MARK: loops

    func forStmt(_ f: ast.ForStmt) throws {
        var ls: ast.Scope? = nil
        if let s = f.Scope {
            ls = s
            enterScope(s)
        }
        if let i = f.Init {
            switch i {
            case .varDecl(let v): try varDecl(v)
            case .expr(let e): try expr(e.Expression)
            default: try stmt(i)
            }
        }
        let perIteration = ls != nil && ls!.NeedsContext
        let top = newLabel()
        let cont = newLabel()
        let end = newLabel()
        let c = pushLoop(f.Labels, breakL: end, continueL: cont)
        if perIteration { emit(.cloneContext) }
        bind(top)
        if let test = f.Test {
            try condition(test, falseLabel: end)
        }
        try stmt(f.Body)
        bind(cont)
        // Each iteration gets its own copy of the loop's let bindings.
        if perIteration { emit(.cloneContext) }
        if let u = f.Update { try expr(u) }
        jump(.jump, top)
        bind(end)
        popControl(c)
        if let s = ls { exitScope(s) }
    }

    /// loopTarget binds a for-in or for-of loop's value (in the
    /// accumulator) to its declaration or target.
    func loopTarget(_ f: ast.ForInStmt) throws {
        if let d = f.Decl {
            try bindPatternFromAcc(d.Declarations[0].Target, initialize: d.Kind != .varKind)
        } else if let t = f.Target {
            try bindPatternFromAcc(t, initialize: false)
        }
    }

    /// enterLoopScope enters a for-in/of iteration's scope with the value
    /// still in the accumulator: entering writes the bindings' TDZ holes
    /// through it.
    func enterLoopScope(_ f: ast.ForInStmt) throws {
        guard let s = f.Scope else { return }
        let v = temp()
        emit(.star, v)
        enterScope(s)
        emit(.ldar, v)
    }

    func forIn(_ f: ast.ForInStmt) throws {
        // for (var x = init in o): Annex B's initializer runs first.
        if let d = f.Decl, let initE = d.Declarations[0].Init {
            try exprNamed(initE, patternName(d.Declarations[0].Target))
            try bindPatternFromAcc(d.Declarations[0].Target, initialize: false)
        }
        if let s = f.Scope { enterScope(s) }
        try expr(f.Right)
        if let s = f.Scope { exitScope(s) }
        let end = newLabel()
        let top = newLabel()
        // null and undefined enumerate nothing.
        jump(.jumpIfNullish, end)
        let en = temp()
        emit(.forInPrepare, en)
        let c = pushLoop(f.Labels, breakL: end, continueL: top)
        bind(top)
        jumpB(.forInNext, en, end)
        try enterLoopScope(f)
        try loopTarget(f)
        try stmt(f.Body)
        if let s = f.Scope { exitScope(s) }
        jump(.jump, top)
        bind(end)
        popControl(c)
    }

    func forOf(_ f: ast.ForInStmt) throws {
        if let s = f.Scope { enterScope(s) }
        try expr(f.Right)
        if let s = f.Scope { exitScope(s) }
        let iter = temps(3)
        emit(f.IsAwait ? .getAsyncIterator : .getIterator, iter)
        let top = newLabel()
        let end = newLabel()
        let loop = pushLoop(f.Labels, breakL: end, continueL: top)
        // A throw out of the body, or a generator's return, closes the
        // iterator: a finally-like handler with the completion registers.
        let kindReg = temp()
        let valueReg = temp()
        let iterCtl = Control(kind: f.IsAwait ? .asyncIterator : .iterator)
        iterCtl.iterReg = iter
        control.append(iterCtl)
        let depth = contextDepth
        let start = t.Code.count
        bind(top)
        if f.IsAwait {
            emit(.ldaUndefined)
            emit(.iteratorNext, iter)
            emit(.awaitOp)
            jumpB(.iteratorResult, iter, endOfLoop(end, iterCtl))
        } else {
            jumpB(.iteratorStep, iter, endOfLoop(end, iterCtl))
        }
        try enterLoopScope(f)
        if let d = f.Decl, d.Kind.IsUsing {
            let val = temp()
            emit(.star, val)
            try withDispose(hasAwait: d.Kind == .awaitUsingKind) {
                try self.loopTarget(f)
                self.emit(.ldar, val)
                self.emit(.addDisposable, self.disposeScopes.last!, d.Kind == .awaitUsingKind ? 1 : 0)
                try self.stmt(f.Body)
            }
        } else {
            try loopTarget(f)
            try stmt(f.Body)
        }
        if let s = f.Scope { exitScope(s) }
        jump(.jump, top)
        let stop = t.Code.count
        popControl(iterCtl)
        // The cleanup: throw (kind 1) or a generator's return (kind 2).
        let cleanup = newLabel()
        let throwPad = newLabel()
        let after = newLabel()
        jump(.jump, after)
        bind(throwPad)
        emit(.star, valueReg)
        emit(.ldaSmi, 1)
        emit(.star, kindReg)
        bind(cleanup)
        emit(.ldaSmi, 1)
        emit(.testStrictEq, kindReg)
        let notThrow = newLabel()
        jump(.jumpIfFalse, notThrow)
        if f.IsAwait {
            // Close without replacing the exception.
            emit(.iteratorCloseThrow, iter)
        } else {
            emit(.iteratorCloseThrow, iter)
        }
        emit(.ldar, valueReg)
        emit(.throwOp)
        bind(notThrow)
        // A return: close the iterator, then keep returning.
        if f.IsAwait {
            let noReturn = newLabel()
            jumpB(.asyncIteratorClose, iter, noReturn)
            emit(.awaitOp)
            bind(noReturn)
        } else {
            emit(.iteratorClose, iter)
        }
        unwind(to: -1, .ret(valueReg))
        t.Handlers.append(bytecode.Handler(start: start, end: stop, target: labelPC(throwPad), isFinally: true, kindReg: int(kindReg), valueReg: int(valueReg), finallyStart: labelPC(cleanup), contextDepth: depth))
        bind(after)
        bind(end)
        popControl(loop)
    }

    /// endOfLoop is where the loop goes when the iterator is done.
    func endOfLoop(_ end: int, _ c: Control) -> int {
        return end
    }

    /// labelPC is a label's address, or -1 if it isn't bound yet (fixed up
    /// by fixHandlers).
    func labelPC(_ l: int) -> int {
        return labels[l]
    }

    // MARK: switch

    func switchStmt(_ sw: ast.SwitchStmt) throws {
        try expr(sw.Discriminant)
        let d = temp()
        emit(.star, d)
        let bs = sw.Scope!
        enterScope(bs)
        var all: [ast.Stmt] = []
        for sc in sw.Cases { all.append(contentsOf: sc.Body) }
        try hoistFunctions(all, bs, skipTop: false)
        let end = newLabel()
        let c = Control(kind: .switchBlock)
        c.labels = sw.Labels
        c.breakLabel = end
        control.append(c)
        func dispatchAndBodies() throws {
            var bodyLabels: [int] = []
            var defaultIndex = -1
            var i = 0
            while i < sw.Cases.count {
                bodyLabels.append(newLabel())
                if let test = sw.Cases[i].Test {
                    try expr(test)
                    emit(.testStrictEq, d)
                    jump(.jumpIfTrue, bodyLabels[i])
                } else {
                    defaultIndex = i
                }
                i += 1
            }
            if defaultIndex >= 0 {
                jump(.jump, bodyLabels[defaultIndex])
            } else {
                jump(.jump, end)
            }
            i = 0
            while i < sw.Cases.count {
                bind(bodyLabels[i])
                for st in sw.Cases[i].Body { try stmt(st) }
                i += 1
            }
        }
        try dispatchAndBodies()
        bind(end)
        popControl(c)
        exitScope(bs)
    }

    // MARK: try

    func tryStmt(_ tr: ast.TryStmt) throws {
        let hasFinally = tr.Finalizer != nil
        var fin: Control? = nil
        let finallyL = newLabel()
        let end = newLabel()
        if hasFinally {
            let f = Control(kind: .finallyBlock)
            f.kindReg = temp()
            f.valueReg = temp()
            f.finallyLabel = finallyL
            control.append(f)
            fin = f
        }
        let depth = contextDepth
        let tryStart = t.Code.count
        try block(tr.Block)
        let tryEnd = t.Code.count
        if hasFinally {
            emit(.ldaSmi, 0)
            emit(.star, fin!.kindReg)
            jump(.jump, finallyL)
        } else {
            jump(.jump, end)
        }
        var catchEnd = tryEnd
        if let h = tr.Handler {
            let catchPC = t.Code.count
            t.Handlers.append(bytecode.Handler(start: tryStart, end: tryEnd, target: catchPC, isFinally: false, contextDepth: depth))
            let cs = tr.CatchScope!
            let ex = temp()
            emit(.star, ex)
            enterScope(cs)
            if let p = tr.Param {
                emit(.ldar, ex)
                try bindPatternFromAcc(p, initialize: true)
            }
            try block(h)
            exitScope(cs)
            catchEnd = t.Code.count
            if hasFinally {
                emit(.ldaSmi, 0)
                emit(.star, fin!.kindReg)
                jump(.jump, finallyL)
            } else {
                jump(.jump, end)
            }
        }
        guard let f = fin else {
            bind(end)
            return
        }
        popControl(f)
        // A throw from the try or the catch lands here: kind 1.
        let throwPad = t.Code.count
        emit(.star, f.valueReg)
        emit(.ldaSmi, 1)
        emit(.star, f.kindReg)
        bind(finallyL)
        let finallyStart = labels[finallyL]
        t.Handlers.append(bytecode.Handler(start: tryStart, end: catchEnd, target: throwPad, isFinally: true, kindReg: int(f.kindReg), valueReg: int(f.valueReg), finallyStart: finallyStart, contextDepth: depth))
        // A finally block's own statements don't change the completion value.
        var savedCompletion: int32 = -1
        if completion >= 0 {
            savedCompletion = temp()
            emit(.ldar, completion)
            emit(.star, savedCompletion)
        }
        try block(tr.Finalizer!)
        if savedCompletion >= 0 {
            emit(.ldar, savedCompletion)
            emit(.star, completion)
        }
        // Dispatch on the completion.
        let normal = newLabel()
        emit(.ldar, f.kindReg)
        jump(.jumpIfFalse, normal)
        // kind 1: rethrow.
        let notThrow = newLabel()
        emit(.ldaSmi, 1)
        emit(.testStrictEq, f.kindReg)
        jump(.jumpIfFalse, notThrow)
        emit(.ldar, f.valueReg)
        emit(.throwOp)
        bind(notThrow)
        // kind 2: a return (a generator's return resumption lands here too).
        let notReturn = newLabel()
        emit(.ldaSmi, 2)
        emit(.testStrictEq, f.kindReg)
        jump(.jumpIfFalse, notReturn)
        unwind(to: -1, .ret(f.valueReg))
        bind(notReturn)
        // kind 3 and up: the jumps that crossed this finally.
        for p in f.pending {
            let next = newLabel()
            emit(.ldaSmi, int32(p.id))
            emit(.testStrictEq, f.kindReg)
            jump(.jumpIfFalse, next)
            unwind(to: p.target, p.action)
            bind(next)
        }
        bind(normal)
        bind(end)
    }

    // MARK: modules

    func exportDecl(_ e: ast.ExportDecl) throws {
        if let d = e.Declaration {
            switch d {
            case .functionDecl:
                break // hoisted
            default:
                try stmt(d)
            }
        } else if let x = e.DefaultExpr {
            try exprNamed(x, "default")
            if let b = scope.Bindings["*default*"] {
                storeBinding(b, name: "*default*", initialize: true)
            }
        }
    }
}
