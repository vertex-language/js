package codegen

import (
    "js/ast"
    "js/token"
    "js/bytecode"
    "js/scope"
)

/// Compile translates a Program AST into an executable BytecodeFunction.
public func Compile(_ program: ast.Program) throws -> bytecode.BytecodeFunction {
    let globalScope = try scope.Analyze(program)
    let c = Compiler(currentScope: globalScope)
    return try c.CompileProgram(program)
}

struct LoopTarget {
    var breakJumps: [int] = []
    var continueJumps: [int] = []
    var continueOffset: int = 0
}

/// Compiler generates bytecode from AST nodes.
final class Compiler {
    var fn: bytecode.BytecodeFunction
    var currentScope: scope.Scope
    var nextRegister: int32 = 0
    var maxRegisters: int32 = 0
    var loopStack: [LoopTarget] = []
    var childScopeIndex: int = 0
    var currentSuperExpr: ast.Expr? = nil
    var isStaticMethod: bool = false

    init(currentScope: scope.Scope, name: string = "") {
        self.fn = bytecode.BytecodeFunction(name: name)
        self.currentScope = currentScope
        let base = int32(currentScope.SlotCount)
        self.nextRegister = base
        self.maxRegisters = base
    }

    func allocateRegister() -> int32 {
        let r = nextRegister
        nextRegister += 1
        if nextRegister > maxRegisters {
            maxRegisters = nextRegister
        }
        return r
    }

    func freeRegister(_ r: int32) {
        if r + 1 == nextRegister {
            nextRegister = r
        }
    }

    func emit(_ instr: bytecode.Instruction) -> int {
        return fn.Emit(instr)
    }

    func patchJump(_ index: int) {
        let offset = int32(fn.Instructions.count - index)
        fn.Instructions[index].Offset = offset
    }

    func patchJumpTo(_ index: int, target: int) {
        let offset = int32(target - index)
        fn.Instructions[index].Offset = offset
    }

    func addStringConstant(_ s: string) -> int32 {
        for i in 0..<fn.Constants.count {
            if case .stringVal(let existing) = fn.Constants[i], existing == s {
                return int32(i)
            }
        }
        return fn.AddConstant(.stringVal(s))
    }

    func addNumberConstant(_ n: float64) -> int32 {
        for i in 0..<fn.Constants.count {
            if case .numberVal(let existing) = fn.Constants[i], existing == n {
                return int32(i)
            }
        }
        return fn.AddConstant(.numberVal(n))
    }

    func CompileProgram(_ program: ast.Program) throws -> bytecode.BytecodeFunction {
        for s in program.Body {
            try compileStmt(s)
        }
        _ = emit(bytecode.Instruction(op: .returnOp))
        fn.RegisterCount = Int(maxRegisters)
        return fn
    }

    func compileStmt(_ s: ast.Stmt) throws {
        switch s {
        case .empty:
            break

        case .expr(let e):
            try compileExpr(e.Expression)

        case .block(let b):
            let prevScope = currentScope
            if childScopeIndex < currentScope.Children.count {
                currentScope = currentScope.Children[childScopeIndex]
                childScopeIndex += 1
            }
            for stmt in b.Statements {
                try compileStmt(stmt)
            }
            currentScope = prevScope

        case .varDecl(let v):
            for d in v.Declarations {
                if let initExpr = d.Init {
                    try compileExpr(initExpr)
                    if currentScope.Kind == .global {
                        let constIdx = addStringConstant(d.Id)
                        _ = emit(bytecode.Instruction(op: .staGlobal, imm: constIdx))
                    }
                    if let binding = currentScope.LookupInCurrentFunction(d.Id) {
                        let reg = int32(binding.Slot)
                        _ = emit(bytecode.Instruction(op: .star, r0: reg))
                    } else {
                        let constIdx = addStringConstant(d.Id)
                        _ = emit(bytecode.Instruction(op: .staGlobal, imm: constIdx))
                    }
                }
            }

        case .functionDecl(let f):
            let fnScope: scope.Scope
            if childScopeIndex < currentScope.Children.count {
                fnScope = currentScope.Children[childScopeIndex]
                childScopeIndex += 1
            } else {
                fnScope = currentScope
            }
            let fnCompiler = Compiler(currentScope: fnScope, name: f.Name)
            fnCompiler.fn.ParameterCount = f.Params.count
            for stmt in f.Body.Statements {
                try fnCompiler.compileStmt(stmt)
            }
            _ = fnCompiler.emit(bytecode.Instruction(op: .ldaUndefined))
            _ = fnCompiler.emit(bytecode.Instruction(op: .returnOp))
            fnCompiler.fn.RegisterCount = Int(fnCompiler.maxRegisters)

            let fnConst = fn.AddConstant(.fnVal(fnCompiler.fn))
            _ = emit(bytecode.Instruction(op: .createClosure, imm: fnConst))
            let constIdx = addStringConstant(f.Name)
            _ = emit(bytecode.Instruction(op: .staGlobal, imm: constIdx))
            if let b = currentScope.LookupInCurrentFunction(f.Name) {
                let reg = int32(b.Slot)
                _ = emit(bytecode.Instruction(op: .star, r0: reg))
            }

        case .ifStmt(let i):
            try compileExpr(i.Test)
            let jumpToElse = emit(bytecode.Instruction(op: .jumpIfFalse))
            try compileStmt(i.Consequent)
            if let alt = i.Alternate {
                let jumpToEnd = emit(bytecode.Instruction(op: .jump))
                patchJump(jumpToElse)
                try compileStmt(alt)
                patchJump(jumpToEnd)
            } else {
                patchJump(jumpToElse)
            }

        case .whileStmt(let w):
            let loopStart = fn.Instructions.count
            loopStack.append(LoopTarget(continueOffset: loopStart))
            try compileExpr(w.Test)
            let exitJump = emit(bytecode.Instruction(op: .jumpIfFalse))
            try compileStmt(w.Body)
            _ = emit(bytecode.Instruction(op: .jump, offset: int32(loopStart - fn.Instructions.count)))
            patchJump(exitJump)
            let loopTarget = loopStack.removeLast()
            for bJump in loopTarget.breakJumps {
                patchJump(bJump)
            }
            for cJump in loopTarget.continueJumps {
                patchJumpTo(cJump, target: loopStart)
            }

        case .doWhileStmt(let d):
            let loopStart = fn.Instructions.count
            loopStack.append(LoopTarget(continueOffset: loopStart))
            try compileStmt(d.Body)
            try compileExpr(d.Test)
            _ = emit(bytecode.Instruction(op: .jumpIfTrue, offset: int32(loopStart - fn.Instructions.count)))
            let loopTarget = loopStack.removeLast()
            for bJump in loopTarget.breakJumps {
                patchJump(bJump)
            }
            for cJump in loopTarget.continueJumps {
                patchJumpTo(cJump, target: loopStart)
            }

        case .forStmt(let f):
            if let is_ = f.InitStmt {
                try compileStmt(is_)
            } else if let ie = f.InitExpr {
                try compileExpr(ie)
            }
            let loopStart = fn.Instructions.count
            var exitJump: int? = nil
            if let test = f.Test {
                try compileExpr(test)
                exitJump = emit(bytecode.Instruction(op: .jumpIfFalse))
            }
            loopStack.append(LoopTarget(continueOffset: loopStart))
            try compileStmt(f.Body)

            let continueTarget = fn.Instructions.count
            if let update = f.Update {
                try compileExpr(update)
            }
            _ = emit(bytecode.Instruction(op: .jump, offset: int32(loopStart - fn.Instructions.count)))
            if let ej = exitJump {
                patchJump(ej)
            }
            let loopTarget = loopStack.removeLast()
            for bJump in loopTarget.breakJumps {
                patchJump(bJump)
            }
            for cJump in loopTarget.continueJumps {
                patchJumpTo(cJump, target: continueTarget)
            }

        case .returnStmt(let r):
            if let arg = r.Argument {
                try compileExpr(arg)
            } else {
                _ = emit(bytecode.Instruction(op: .ldaUndefined))
            }
            _ = emit(bytecode.Instruction(op: .returnOp))

        case .breakStmt:
            if !loopStack.isEmpty {
                let j = emit(bytecode.Instruction(op: .jump))
                loopStack[loopStack.count - 1].breakJumps.append(j)
            }

        case .continueStmt:
            if !loopStack.isEmpty {
                let j = emit(bytecode.Instruction(op: .jump))
                loopStack[loopStack.count - 1].continueJumps.append(j)
            }

        case .throwStmt(let t):
            try compileExpr(t.Argument)
            _ = emit(bytecode.Instruction(op: .throwOp))

        case .switchStmt(let sw):
            try compileExpr(sw.Discriminant)
            let discReg = allocateRegister()
            _ = emit(bytecode.Instruction(op: .star, r0: discReg))
            var caseJumps: [(testJump: int, caseIdx: int)] = []
            var defaultIdx: int? = nil

            for idx in 0..<sw.Cases.count {
                let c = sw.Cases[idx]
                if let t = c.Test {
                    try compileExpr(t)
                    _ = emit(bytecode.Instruction(op: .testStrictEqual, r0: discReg))
                    let j = emit(bytecode.Instruction(op: .jumpIfTrue))
                    caseJumps.append((testJump: j, caseIdx: idx))
                } else {
                    defaultIdx = idx
                }
            }
            let jumpToDefault = emit(bytecode.Instruction(op: .jump))
            var endJumps: [int] = []

            for idx in 0..<sw.Cases.count {
                for cj in caseJumps where cj.caseIdx == idx {
                    patchJump(cj.testJump)
                }
                if defaultIdx == idx {
                    patchJump(jumpToDefault)
                }
                for s in sw.Cases[idx].Consequent {
                    try compileStmt(s)
                }
            }
            if defaultIdx == nil {
                patchJump(jumpToDefault)
            }
            for ej in endJumps {
                patchJump(ej)
            }
            freeRegister(discReg)

        case .tryStmt(let tr):
            try compileStmt(.block(tr.Block))
            if let h = tr.Handler {
                try compileStmt(.block(h.Body))
            }
            if let f = tr.Finalizer {
                try compileStmt(.block(f))
            }

        case .classDecl(let c):
            try compileClass(name: c.Name, superClass: c.SuperClass, elements: c.Elements, isExpr: false)

        case .forInStmt, .forOfStmt:
            break
        }
    }

    func compileExpr(_ e: ast.Expr) throws {
        switch e {
        case .number(let n):
            let constIdx = addNumberConstant(n.Value)
            _ = emit(bytecode.Instruction(op: .ldaConstant, imm: constIdx))

        case .string(let s):
            let constIdx = addStringConstant(s.Value)
            _ = emit(bytecode.Instruction(op: .ldaConstant, imm: constIdx))

        case .boolean(let b):
            _ = emit(bytecode.Instruction(op: b.Value ? .ldaTrue : .ldaFalse))

        case .nullLit:
            _ = emit(bytecode.Instruction(op: .ldaNull))

        case .undefinedLit:
            _ = emit(bytecode.Instruction(op: .ldaUndefined))

        case .thisExpr:
            _ = emit(bytecode.Instruction(op: .ldar, r0: 0)) // r0 is receiver 'this'

        case .identifier(let id):
            if let b = currentScope.LookupInCurrentFunction(id.Name) {
                let reg = int32(b.Slot)
                _ = emit(bytecode.Instruction(op: .ldar, r0: reg))
            } else {
                let constIdx = addStringConstant(id.Name)
                _ = emit(bytecode.Instruction(op: .ldaGlobal, imm: constIdx))
            }

        case .binary(let b):
            try compileExpr(b.Left)
            let leftReg = allocateRegister()
            _ = emit(bytecode.Instruction(op: .star, r0: leftReg))
            try compileExpr(b.Right)
            switch b.Op {
            case .add: _ = emit(bytecode.Instruction(op: .add, r0: leftReg))
            case .sub: _ = emit(bytecode.Instruction(op: .sub, r0: leftReg))
            case .mul: _ = emit(bytecode.Instruction(op: .mul, r0: leftReg))
            case .div: _ = emit(bytecode.Instruction(op: .div, r0: leftReg))
            case .mod: _ = emit(bytecode.Instruction(op: .mod, r0: leftReg))
            case .exp: _ = emit(bytecode.Instruction(op: .exp, r0: leftReg))
            case .bitAnd: _ = emit(bytecode.Instruction(op: .bitAnd, r0: leftReg))
            case .bitOr: _ = emit(bytecode.Instruction(op: .bitOr, r0: leftReg))
            case .bitXor: _ = emit(bytecode.Instruction(op: .bitXor, r0: leftReg))
            case .shl: _ = emit(bytecode.Instruction(op: .shiftLeft, r0: leftReg))
            case .shr: _ = emit(bytecode.Instruction(op: .shiftRight, r0: leftReg))
            case .ushr: _ = emit(bytecode.Instruction(op: .shiftRightLogical, r0: leftReg))
            case .eq: _ = emit(bytecode.Instruction(op: .testEqual, r0: leftReg))
            case .strictEq: _ = emit(bytecode.Instruction(op: .testStrictEqual, r0: leftReg))
            case .notEq: _ = emit(bytecode.Instruction(op: .testNotEqual, r0: leftReg))
            case .strictNotEq: _ = emit(bytecode.Instruction(op: .testStrictNotEqual, r0: leftReg))
            case .less: _ = emit(bytecode.Instruction(op: .testLessThan, r0: leftReg))
            case .greater: _ = emit(bytecode.Instruction(op: .testGreaterThan, r0: leftReg))
            case .lessEq: _ = emit(bytecode.Instruction(op: .testLessThanOrEqual, r0: leftReg))
            case .greaterEq: _ = emit(bytecode.Instruction(op: .testGreaterThanOrEqual, r0: leftReg))
            case .kIn: _ = emit(bytecode.Instruction(op: .testIn, r0: leftReg))
            case .kInstanceof: _ = emit(bytecode.Instruction(op: .testInstanceOf, r0: leftReg))
            default: break
            }
            freeRegister(leftReg)

        case .logical(let l):
            try compileExpr(l.Left)
            if l.Op == .logicalAnd {
                let jump = emit(bytecode.Instruction(op: .jumpIfFalse))
                try compileExpr(l.Right)
                patchJump(jump)
            } else if l.Op == .logicalOr {
                let jump = emit(bytecode.Instruction(op: .jumpIfTrue))
                try compileExpr(l.Right)
                patchJump(jump)
            } else if l.Op == .nullishCoalesce {
                let jump = emit(bytecode.Instruction(op: .jumpIfNull))
                try compileExpr(l.Right)
                patchJump(jump)
            }

        case .unary(let u):
            if u.Op == .inc || u.Op == .dec {
                if case .identifier(let id) = u.Argument {
                    let b = currentScope.LookupInCurrentFunction(id.Name)
                    let isLocal = b != nil
                    let localSlot = isLocal ? int32(b!.Slot) : int32(0)
                    let nameConst = isLocal ? int32(0) : addStringConstant(id.Name)

                    if isLocal {
                        _ = emit(bytecode.Instruction(op: .ldar, r0: localSlot))
                    } else {
                        _ = emit(bytecode.Instruction(op: .ldaGlobal, imm: nameConst))
                    }

                    let oldReg = allocateRegister()
                    _ = emit(bytecode.Instruction(op: .star, r0: oldReg))

                    let oneConst = addNumberConstant(1.0)
                    _ = emit(bytecode.Instruction(op: .ldaConstant, imm: oneConst))
                    if u.Op == .inc {
                        _ = emit(bytecode.Instruction(op: .add, r0: oldReg))
                    } else {
                        _ = emit(bytecode.Instruction(op: .sub, r0: oldReg))
                    }

                    if isLocal {
                        _ = emit(bytecode.Instruction(op: .star, r0: localSlot))
                    } else {
                        _ = emit(bytecode.Instruction(op: .staGlobal, imm: nameConst))
                    }

                    if !u.Prefix {
                        _ = emit(bytecode.Instruction(op: .ldar, r0: oldReg))
                    }
                    freeRegister(oldReg)
                    return
                }
            }
            try compileExpr(u.Argument)
            switch u.Op {
            case .sub: _ = emit(bytecode.Instruction(op: .negate))
            case .bitNot: _ = emit(bytecode.Instruction(op: .bitwiseNot))
            case .logicalNot: _ = emit(bytecode.Instruction(op: .toBooleanLogicalNot))
            case .kTypeof: _ = emit(bytecode.Instruction(op: .typeOf))
            case .kVoid: _ = emit(bytecode.Instruction(op: .ldaUndefined))
            default: break
            }

        case .conditional(let c):
            try compileExpr(c.Test)
            let jumpToAlt = emit(bytecode.Instruction(op: .jumpIfFalse))
            try compileExpr(c.Consequent)
            let jumpToEnd = emit(bytecode.Instruction(op: .jump))
            patchJump(jumpToAlt)
            try compileExpr(c.Alternate)
            patchJump(jumpToEnd)

        case .assign(let a):
            if a.Op == .assign {
                try compileExpr(a.Right)
                if case .identifier(let id) = a.Left {
                    if currentScope.Kind == .global {
                        let constIdx = addStringConstant(id.Name)
                        _ = emit(bytecode.Instruction(op: .staGlobal, imm: constIdx))
                    }
                    if let b = currentScope.LookupInCurrentFunction(id.Name) {
                        let reg = int32(b.Slot)
                        _ = emit(bytecode.Instruction(op: .star, r0: reg))
                    } else {
                        let constIdx = addStringConstant(id.Name)
                        _ = emit(bytecode.Instruction(op: .staGlobal, imm: constIdx))
                    }
                } else if case .member(let m) = a.Left {
                    let valReg = allocateRegister()
                    _ = emit(bytecode.Instruction(op: .star, r0: valReg))
                    try compileExpr(m.Object)
                    let objReg = allocateRegister()
                    _ = emit(bytecode.Instruction(op: .star, r0: objReg))
                    if m.Computed {
                        try compileExpr(m.Property)
                        let keyReg = allocateRegister()
                        _ = emit(bytecode.Instruction(op: .star, r0: keyReg))
                        _ = emit(bytecode.Instruction(op: .ldar, r0: valReg))
                        _ = emit(bytecode.Instruction(op: .staKeyedProperty, r0: objReg, r1: keyReg))
                        freeRegister(keyReg)
                    } else if case .identifier(let propId) = m.Property {
                        let constIdx = addStringConstant(propId.Name)
                        _ = emit(bytecode.Instruction(op: .ldar, r0: valReg))
                        _ = emit(bytecode.Instruction(op: .staNamedProperty, r0: objReg, imm: constIdx))
                    }
                    freeRegister(objReg)
                    _ = emit(bytecode.Instruction(op: .ldar, r0: valReg))
                    freeRegister(valReg)
                }
            } else {
                if case .identifier(let id) = a.Left {
                    let b = currentScope.LookupInCurrentFunction(id.Name)
                    let isLocal = b != nil
                    let localSlot = isLocal ? int32(b!.Slot) : int32(0)
                    let nameConst = isLocal ? int32(0) : addStringConstant(id.Name)

                    let leftReg: int32
                    if isLocal {
                        leftReg = localSlot
                    } else {
                        _ = emit(bytecode.Instruction(op: .ldaGlobal, imm: nameConst))
                        leftReg = allocateRegister()
                        _ = emit(bytecode.Instruction(op: .star, r0: leftReg))
                    }

                    try compileExpr(a.Right)

                    switch a.Op {
                    case .addAssign: _ = emit(bytecode.Instruction(op: .add, r0: leftReg))
                    case .subAssign: _ = emit(bytecode.Instruction(op: .sub, r0: leftReg))
                    case .mulAssign: _ = emit(bytecode.Instruction(op: .mul, r0: leftReg))
                    case .divAssign: _ = emit(bytecode.Instruction(op: .div, r0: leftReg))
                    case .modAssign: _ = emit(bytecode.Instruction(op: .mod, r0: leftReg))
                    case .expAssign: _ = emit(bytecode.Instruction(op: .exp, r0: leftReg))
                    case .andAssign: _ = emit(bytecode.Instruction(op: .bitAnd, r0: leftReg))
                    case .orAssign:  _ = emit(bytecode.Instruction(op: .bitOr, r0: leftReg))
                    case .xorAssign: _ = emit(bytecode.Instruction(op: .bitXor, r0: leftReg))
                    case .shlAssign: _ = emit(bytecode.Instruction(op: .shiftLeft, r0: leftReg))
                    case .shrAssign: _ = emit(bytecode.Instruction(op: .shiftRight, r0: leftReg))
                    case .ushrAssign: _ = emit(bytecode.Instruction(op: .shiftRightLogical, r0: leftReg))
                    default: break
                    }

                    if isLocal {
                        _ = emit(bytecode.Instruction(op: .star, r0: localSlot))
                    } else {
                        _ = emit(bytecode.Instruction(op: .staGlobal, imm: nameConst))
                        freeRegister(leftReg)
                    }
                }
            }

        case .member(let m):
            if case .superExpr = m.Object {
                if let sup = currentSuperExpr {
                    let targetReg = allocateRegister()
                    try compileExpr(sup)
                    _ = emit(bytecode.Instruction(op: .star, r0: targetReg))
                    if !isStaticMethod {
                        let protoConst = addStringConstant("prototype")
                        _ = emit(bytecode.Instruction(op: .ldaNamedProperty, r0: targetReg, imm: protoConst))
                        _ = emit(bytecode.Instruction(op: .star, r0: targetReg))
                    }
                    if m.Computed {
                        try compileExpr(m.Property)
                        _ = emit(bytecode.Instruction(op: .ldaKeyedProperty, r0: targetReg))
                    } else if case .identifier(let propId) = m.Property {
                        let constIdx = addStringConstant(propId.Name)
                        _ = emit(bytecode.Instruction(op: .ldaNamedProperty, r0: targetReg, imm: constIdx))
                    }
                    freeRegister(targetReg)
                    return
                }
            }
            try compileExpr(m.Object)
            let objReg = allocateRegister()
            _ = emit(bytecode.Instruction(op: .star, r0: objReg))
            if m.Computed {
                try compileExpr(m.Property)
                _ = emit(bytecode.Instruction(op: .ldaKeyedProperty, r0: objReg))
            } else if case .identifier(let propId) = m.Property {
                let constIdx = addStringConstant(propId.Name)
                _ = emit(bytecode.Instruction(op: .ldaNamedProperty, r0: objReg, imm: constIdx))
            }
            freeRegister(objReg)

        case .call(let c):
            if case .superExpr = c.Callee {
                if let sup = currentSuperExpr {
                    let calleeReg = allocateRegister()
                    let receiverReg = allocateRegister()
                    try compileExpr(sup)
                    _ = emit(bytecode.Instruction(op: .star, r0: calleeReg))
                    _ = emit(bytecode.Instruction(op: .ldar, r0: 0)) // r0 is receiver 'this'
                    _ = emit(bytecode.Instruction(op: .star, r0: receiverReg))
                    var argRegs: [int32] = []
                    for arg in c.Arguments {
                        try compileExpr(arg)
                        let aReg = allocateRegister()
                        _ = emit(bytecode.Instruction(op: .star, r0: aReg))
                        argRegs.append(aReg)
                    }
                    let firstArg = argRegs.isEmpty ? 0 : argRegs[0]
                    _ = emit(bytecode.Instruction(op: .call, r0: calleeReg, r1: receiverReg, r2: firstArg, imm: int32(argRegs.count)))
                    for ar in argRegs.reversed() {
                        freeRegister(ar)
                    }
                    freeRegister(receiverReg)
                    freeRegister(calleeReg)
                    return
                }
            }
            if case .member(let m) = c.Callee, case .superExpr = m.Object {
                if let sup = currentSuperExpr {
                    let calleeReg = allocateRegister()
                    let receiverReg = allocateRegister()
                    let targetReg = allocateRegister()
                    try compileExpr(sup)
                    _ = emit(bytecode.Instruction(op: .star, r0: targetReg))
                    if !isStaticMethod {
                        let protoConst = addStringConstant("prototype")
                        _ = emit(bytecode.Instruction(op: .ldaNamedProperty, r0: targetReg, imm: protoConst))
                        _ = emit(bytecode.Instruction(op: .star, r0: targetReg))
                    }
                    if m.Computed {
                        try compileExpr(m.Property)
                        _ = emit(bytecode.Instruction(op: .ldaKeyedProperty, r0: targetReg))
                    } else if case .identifier(let propId) = m.Property {
                        let constIdx = addStringConstant(propId.Name)
                        _ = emit(bytecode.Instruction(op: .ldaNamedProperty, r0: targetReg, imm: constIdx))
                    }
                    _ = emit(bytecode.Instruction(op: .star, r0: calleeReg))
                    freeRegister(targetReg)

                    _ = emit(bytecode.Instruction(op: .ldar, r0: 0)) // receiver 'this'
                    _ = emit(bytecode.Instruction(op: .star, r0: receiverReg))

                    var argRegs: [int32] = []
                    for arg in c.Arguments {
                        try compileExpr(arg)
                        let aReg = allocateRegister()
                        _ = emit(bytecode.Instruction(op: .star, r0: aReg))
                        argRegs.append(aReg)
                    }
                    let firstArg = argRegs.isEmpty ? 0 : argRegs[0]
                    _ = emit(bytecode.Instruction(op: .call, r0: calleeReg, r1: receiverReg, r2: firstArg, imm: int32(argRegs.count)))
                    for ar in argRegs.reversed() {
                        freeRegister(ar)
                    }
                    freeRegister(receiverReg)
                    freeRegister(calleeReg)
                    return
                }
            }

            let calleeReg = allocateRegister()
            let receiverReg = allocateRegister()

            if case .member(let m) = c.Callee {
                try compileExpr(m.Object)
                _ = emit(bytecode.Instruction(op: .star, r0: receiverReg))
                if m.Computed {
                    try compileExpr(m.Property)
                    _ = emit(bytecode.Instruction(op: .ldaKeyedProperty, r0: receiverReg))
                } else if case .identifier(let propId) = m.Property {
                    let constIdx = addStringConstant(propId.Name)
                    _ = emit(bytecode.Instruction(op: .ldaNamedProperty, r0: receiverReg, imm: constIdx))
                }
                _ = emit(bytecode.Instruction(op: .star, r0: calleeReg))
            } else {
                try compileExpr(c.Callee)
                _ = emit(bytecode.Instruction(op: .star, r0: calleeReg))
                _ = emit(bytecode.Instruction(op: .ldaUndefined))
                _ = emit(bytecode.Instruction(op: .star, r0: receiverReg))
            }

            var argRegs: [int32] = []
            for arg in c.Arguments {
                try compileExpr(arg)
                let aReg = allocateRegister()
                _ = emit(bytecode.Instruction(op: .star, r0: aReg))
                argRegs.append(aReg)
            }
            let firstArg = argRegs.isEmpty ? 0 : argRegs[0]
            _ = emit(bytecode.Instruction(op: .call, r0: calleeReg, r1: receiverReg, r2: firstArg, imm: int32(argRegs.count)))
            for ar in argRegs.reversed() {
                freeRegister(ar)
            }
            freeRegister(receiverReg)
            freeRegister(calleeReg)

        case .array(let a):
            _ = emit(bytecode.Instruction(op: .createArrayLiteral, imm: int32(a.Elements.count)))
            let arrReg = allocateRegister()
            _ = emit(bytecode.Instruction(op: .star, r0: arrReg))
            for idx in 0..<a.Elements.count {
                if let elem = a.Elements[idx] {
                    let keyIdx = addNumberConstant(float64(idx))
                    let keyReg = allocateRegister()
                    _ = emit(bytecode.Instruction(op: .ldaConstant, imm: keyIdx))
                    _ = emit(bytecode.Instruction(op: .star, r0: keyReg))
                    try compileExpr(elem)
                    _ = emit(bytecode.Instruction(op: .staKeyedProperty, r0: arrReg, r1: keyReg))
                    freeRegister(keyReg)
                }
            }
            _ = emit(bytecode.Instruction(op: .ldar, r0: arrReg))
            freeRegister(arrReg)

        case .object(let o):
            _ = emit(bytecode.Instruction(op: .createObjectLiteral))
            let objReg = allocateRegister()
            _ = emit(bytecode.Instruction(op: .star, r0: objReg))
            for prop in o.Properties {
                if prop.Computed {
                    try compileExpr(prop.Key)
                    let keyReg = allocateRegister()
                    _ = emit(bytecode.Instruction(op: .star, r0: keyReg))
                    try compileExpr(prop.Value)
                    _ = emit(bytecode.Instruction(op: .staKeyedProperty, r0: objReg, r1: keyReg))
                    freeRegister(keyReg)
                } else if case .identifier(let id) = prop.Key {
                    let constIdx = addStringConstant(id.Name)
                    try compileExpr(prop.Value)
                    _ = emit(bytecode.Instruction(op: .staNamedProperty, r0: objReg, imm: constIdx))
                } else if case .string(let s) = prop.Key {
                    let constIdx = addStringConstant(s.Value)
                    try compileExpr(prop.Value)
                    _ = emit(bytecode.Instruction(op: .staNamedProperty, r0: objReg, imm: constIdx))
                }
            }
            _ = emit(bytecode.Instruction(op: .ldar, r0: objReg))
            freeRegister(objReg)

        case .function(let f):
            let fnScope: scope.Scope
            if childScopeIndex < currentScope.Children.count {
                fnScope = currentScope.Children[childScopeIndex]
                childScopeIndex += 1
            } else {
                fnScope = currentScope
            }
            let fnCompiler = Compiler(currentScope: fnScope, name: f.Id ?? "")
            fnCompiler.fn.ParameterCount = f.Params.count
            for stmt in f.Body.Statements {
                try fnCompiler.compileStmt(stmt)
            }
            _ = fnCompiler.emit(bytecode.Instruction(op: .ldaUndefined))
            _ = fnCompiler.emit(bytecode.Instruction(op: .returnOp))
            fnCompiler.fn.RegisterCount = Int(fnCompiler.maxRegisters)

            let fnConst = fn.AddConstant(.fnVal(fnCompiler.fn))
            _ = emit(bytecode.Instruction(op: .createClosure, imm: fnConst))

        case .arrow(let a):
            let fnScope: scope.Scope
            if childScopeIndex < currentScope.Children.count {
                fnScope = currentScope.Children[childScopeIndex]
                childScopeIndex += 1
            } else {
                fnScope = currentScope
            }
            let fnCompiler = Compiler(currentScope: fnScope, name: "arrow")
            fnCompiler.fn.ParameterCount = a.Params.count
            if let bStmt = a.BodyStmt {
                for s in bStmt.Statements {
                    try fnCompiler.compileStmt(s)
                }
                _ = fnCompiler.emit(bytecode.Instruction(op: .ldaUndefined))
                _ = fnCompiler.emit(bytecode.Instruction(op: .returnOp))
            } else if let bExpr = a.BodyExpr {
                try fnCompiler.compileExpr(bExpr)
                _ = fnCompiler.emit(bytecode.Instruction(op: .returnOp))
            }
            fnCompiler.fn.RegisterCount = Int(fnCompiler.maxRegisters)
            let fnConst = fn.AddConstant(.fnVal(fnCompiler.fn))
            _ = emit(bytecode.Instruction(op: .createClosure, imm: fnConst))

        case .sequence(let s):
            for item in s.Expressions {
                try compileExpr(item)
            }

        case .template(let t):
            if !t.Quasis.isEmpty {
                let constIdx = addStringConstant(t.Quasis[0])
                _ = emit(bytecode.Instruction(op: .ldaConstant, imm: constIdx))
            } else {
                _ = emit(bytecode.Instruction(op: .ldaUndefined))
            }

        case .newExpr(let n):
            let calleeReg = allocateRegister()
            let receiverReg = allocateRegister()

            try compileExpr(n.Callee)
            _ = emit(bytecode.Instruction(op: .star, r0: calleeReg))
            _ = emit(bytecode.Instruction(op: .ldaUndefined))
            _ = emit(bytecode.Instruction(op: .star, r0: receiverReg))

            var argRegs: [int32] = []
            for arg in n.Arguments {
                try compileExpr(arg)
                let aReg = allocateRegister()
                _ = emit(bytecode.Instruction(op: .star, r0: aReg))
                argRegs.append(aReg)
            }
            let firstArg = argRegs.isEmpty ? 0 : argRegs[0]
            _ = emit(bytecode.Instruction(op: .construct, r0: calleeReg, r1: receiverReg, r2: firstArg, imm: int32(argRegs.count)))
            for ar in argRegs.reversed() {
                freeRegister(ar)
            }
            freeRegister(receiverReg)
            freeRegister(calleeReg)

        case .classExpr(let c):
            try compileClass(name: c.Name, superClass: c.SuperClass, elements: c.Elements, isExpr: true)

        case .superExpr:
            _ = emit(bytecode.Instruction(op: .ldaUndefined))
        }
    }

    func compileClass(name: string?, superClass: ast.Expr?, elements: [ast.ClassElement], isExpr: bool) throws {
        var superExpr: ast.Expr? = nil
        var superReg: int32? = nil
        if let sc = superClass {
            superExpr = sc
            try compileExpr(sc)
            let sReg = allocateRegister()
            _ = emit(bytecode.Instruction(op: .star, r0: sReg))
            superReg = sReg
        }

        // Find constructor
        var ctorElement: ast.ClassElement? = nil
        for el in elements {
            if el.Kind == .constructor {
                ctorElement = el
                break
            }
        }

        let ctorParams: [string]
        let ctorBody: ast.BlockStmt
        if let el = ctorElement {
            ctorParams = el.Value.Params
            ctorBody = el.Value.Body
        } else {
            ctorParams = []
            if superExpr != nil {
                ctorBody = ast.BlockStmt(statements: [
                    ast.Stmt.expr(ast.ExprStmt(ast.Expr.call(ast.CallExpr(callee: .superExpr(ast.SuperExpr()), arguments: []))))
                ])
            } else {
                ctorBody = ast.BlockStmt(statements: [])
            }
        }

        let ctorScope: scope.Scope
        if ctorElement != nil && childScopeIndex < currentScope.Children.count {
            ctorScope = currentScope.Children[childScopeIndex]
            childScopeIndex += 1
        } else {
            ctorScope = scope.Scope(kind: .function, parent: currentScope)
        }

        let ctorCompiler = Compiler(currentScope: ctorScope, name: name ?? "")
        ctorCompiler.currentSuperExpr = superExpr
        ctorCompiler.isStaticMethod = false
        ctorCompiler.fn.ParameterCount = ctorParams.count
        for s in ctorBody.Statements {
            try ctorCompiler.compileStmt(s)
        }
        _ = ctorCompiler.emit(bytecode.Instruction(op: .ldaUndefined))
        _ = ctorCompiler.emit(bytecode.Instruction(op: .returnOp))
        ctorCompiler.fn.RegisterCount = Int(ctorCompiler.maxRegisters)

        let ctorConst = fn.AddConstant(.fnVal(ctorCompiler.fn))
        _ = emit(bytecode.Instruction(op: .createClosure, imm: ctorConst))
        let ctorReg = allocateRegister()
        _ = emit(bytecode.Instruction(op: .star, r0: ctorReg))

        let protoConst = addStringConstant("prototype")

        // Get Sub.prototype into subProtoReg
        _ = emit(bytecode.Instruction(op: .ldaNamedProperty, r0: ctorReg, imm: protoConst))
        let subProtoReg = allocateRegister()
        _ = emit(bytecode.Instruction(op: .star, r0: subProtoReg))

        if let sReg = superReg {
            // Set Sub.__proto__ = Super
            _ = emit(bytecode.Instruction(op: .ldar, r0: sReg))
            _ = emit(bytecode.Instruction(op: .setProto, r0: ctorReg))

            // Set Sub.prototype.__proto__ = Super.prototype
            _ = emit(bytecode.Instruction(op: .ldaNamedProperty, r0: sReg, imm: protoConst))
            _ = emit(bytecode.Instruction(op: .setProto, r0: subProtoReg))
        }

        // Attach methods
        for el in elements {
            if el.Kind == .constructor { continue }

            let mScope: scope.Scope
            if childScopeIndex < currentScope.Children.count {
                mScope = currentScope.Children[childScopeIndex]
                childScopeIndex += 1
            } else {
                mScope = scope.Scope(kind: .function, parent: currentScope)
            }

            var methodName = ""
            if case .identifier(let id) = el.Key {
                methodName = id.Name
            } else if case .string(let s) = el.Key {
                methodName = s.Value
            }

            let mCompiler = Compiler(currentScope: mScope, name: methodName)
            mCompiler.currentSuperExpr = superExpr
            mCompiler.isStaticMethod = el.IsStatic
            mCompiler.fn.ParameterCount = el.Value.Params.count
            for s in el.Value.Body.Statements {
                try mCompiler.compileStmt(s)
            }
            _ = mCompiler.emit(bytecode.Instruction(op: .ldaUndefined))
            _ = mCompiler.emit(bytecode.Instruction(op: .returnOp))
            mCompiler.fn.RegisterCount = Int(mCompiler.maxRegisters)

            let mConst = fn.AddConstant(.fnVal(mCompiler.fn))
            _ = emit(bytecode.Instruction(op: .createClosure, imm: mConst))

            let targetReg = el.IsStatic ? ctorReg : subProtoReg

            if el.Computed {
                let mReg = allocateRegister()
                _ = emit(bytecode.Instruction(op: .star, r0: mReg))
                try compileExpr(el.Key)
                let keyReg = allocateRegister()
                _ = emit(bytecode.Instruction(op: .star, r0: keyReg))
                _ = emit(bytecode.Instruction(op: .ldar, r0: mReg))
                _ = emit(bytecode.Instruction(op: .staKeyedProperty, r0: targetReg, r1: keyReg))
                freeRegister(keyReg)
                freeRegister(mReg)
            } else if !methodName.isEmpty {
                let keyConst = addStringConstant(methodName)
                _ = emit(bytecode.Instruction(op: .staNamedProperty, r0: targetReg, imm: keyConst))
            }
        }

        freeRegister(subProtoReg)
        if let sReg = superReg {
            freeRegister(sReg)
        }

        if let className = name, !isExpr {
            _ = emit(bytecode.Instruction(op: .ldar, r0: ctorReg))
            if currentScope.Kind == .global {
                let constIdx = addStringConstant(className)
                _ = emit(bytecode.Instruction(op: .staGlobal, imm: constIdx))
            }
            if let b = currentScope.LookupInCurrentFunction(className) {
                let reg = int32(b.Slot)
                _ = emit(bytecode.Instruction(op: .star, r0: reg))
            } else {
                let constIdx = addStringConstant(className)
                _ = emit(bytecode.Instruction(op: .staGlobal, imm: constIdx))
            }
            freeRegister(ctorReg)
        } else {
            _ = emit(bytecode.Instruction(op: .ldar, r0: ctorReg))
            freeRegister(ctorReg)
        }
    }
}
