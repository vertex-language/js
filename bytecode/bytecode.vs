// Package bytecode is the instruction set the compiler emits and the
// interpreter runs: a register machine with an accumulator, after V8's
// Ignition. Most instructions read an operand register and the
// accumulator and leave their result in the accumulator.
//
// Operands are A, B and C. Registers are frame slots; context slots are
// named by depth (how many contexts out) and index; constants index the
// function's pool; jump targets are absolute instruction indexes.
package bytecode

import (
    "js/str"
    "js/value"
)

public enum Opcode: Equatable {
    // Accumulator loads.
    case ldaUndefined
    case ldaNull
    case ldaTrue
    case ldaFalse
    case ldaEmpty            // the hole: an uninitialized let, const or class
    case ldaSmi              // acc = A
    case ldaConst            // acc = constant A
    case ldar                // acc = r[A]
    case star                // r[A] = acc
    case mov                 // r[B] = r[A]

    // The frame.
    case ldaArg              // acc = argument A, or undefined
    case createRest          // acc = an array of the arguments from A on
    case createArguments     // acc = the arguments object; A = 1 for a mapped one
    case ldaThis             // acc = this (checked in derived constructors)
    case ldaNewTarget
    case ldaCallee           // acc = the running function
    case ldaHomeObject       // acc = the running method's home object

    // Contexts.
    case pushContext         // enter a scope: A slots, scope info B (-1 for none)
    case popContext
    case cloneContext        // replace the current context with a copy (per-iteration bindings)
    case ldaCtx              // acc = context(A).slot[B]
    case ldaCtxChecked       // same, throwing a ReferenceError for constant C's name if it is the hole
    case staCtx              // context(A).slot[B] = acc
    case checkHole           // throw a ReferenceError for constant B's name if r[A] is the hole
    case checkHoleCtx        // same for context(A).slot[B], name constant C
    case throwIfHole         // throw a ReferenceError for constant A's name if acc is the hole
    case throwConstAssign    // TypeError: assignment to constant variable A

    // Globals and dynamic names.
    case ldaGlobal           // acc = the global named by constant A; ReferenceError if none
    case ldaGlobalTypeof     // same, undefined if none (for typeof)
    case staGlobal           // assign the global named by A; B = 1 in strict code
    case initGlobalLexical   // initialize the top-level let/const/class A from acc
    case declareGlobals      // GlobalDeclarationInstantiation with declarations constant A
    case ldaLookup           // acc = the name A, resolved through contexts, with and eval scopes
    case ldaLookupTypeof
    case ldaLookupThis       // acc = name A; r[B] = the with object it came from, or undefined
    case staLookup           // assign name A; B = 1 in strict code
    case deleteLookup        // acc = delete name A
    case declareEvalVar      // a sloppy eval's var A: declare it in the caller's var scope
    case declareEvalFunction // same, then assign acc to it

    // Properties.
    case getNamed            // acc = r[A][key constant B]
    case getKeyed            // acc = r[A][acc]
    case setNamed            // r[A][key B] = acc; C = 1 in strict code
    case setKeyed            // r[A][r[B]] = acc; C = 1 in strict code
    case defineNamed         // CreateDataProperty(r[A], key B, acc)
    case defineKeyed         // CreateDataProperty(r[A], r[B], acc)
    case defineGetter        // define getter acc on r[A] for key r[B]; C = 1 if enumerable
    case defineSetter
    case defineMethod        // define method acc on r[A] for key r[B] (home object r[A]); C = 1 if enumerable
    case setFunctionName     // name the function in acc from key r[A]; B: 0 plain, 1 "get ", 2 "set "
    case setProto            // r[A].[[Prototype]] = acc, if acc is an object or null (__proto__: v)
    case setHomeObject       // the function in acc gets home object r[A] (acc unchanged)
    case deleteProperty      // acc = delete r[A][acc]; B = 1 in strict code
    case getSuper            // acc = super[r[A]]
    case setSuper            // super[r[A]] = acc
    case getPrivate          // acc = r[A].#(private name r[B])
    case setPrivate          // r[A].#(r[B]) = acc
    case definePrivate       // add private field r[B] = acc to r[A]
    case privateIn           // acc = #(r[A]) in acc
    case copyDataProperties  // copy acc's own enumerable properties into r[A]; B = register of an excluded-keys array, or -1
    case toPropertyKey       // acc = ToPropertyKey(acc)
    case requireObjectCoercible // TypeError if acc is null or undefined

    // Operators: acc = r[A] op acc.
    case add
    case sub
    case mul
    case div
    case mod
    case exp
    case bitAnd
    case bitOr
    case bitXor
    case shl
    case sar
    case shr
    case testEq
    case testNe
    case testStrictEq
    case testStrictNe
    case testLt
    case testGt
    case testLe
    case testGe
    case testIn              // acc = r[A] in acc
    case testInstanceOf      // acc = r[A] instanceof acc
    // Unary operators on acc.
    case inc
    case dec
    case negate
    case bitNot
    case not
    case typeOf
    case toNumeric
    case toNumber
    case toString            // for template literals: ToString, which throws on symbols

    // Control flow.
    case jump                // to A
    case jumpIfTrue          // if ToBoolean(acc)
    case jumpIfFalse
    case jumpIfNullish
    case jumpIfNotNullish
    case jumpIfUndefined
    case jumpIfNotUndefined
    case jumpIfEmpty         // if acc is the hole
    case returnOp
    case throwOp
    case throwError          // throw a new error: A = constant message, B = kind (0 TypeError, 1 ReferenceError, 2 SyntaxError, 3 RangeError)
    case debugger

    // Calls.
    case call                // acc = r[A](r[B] ... r[B+C-1]), this undefined
    case callMethod          // acc = r[A] called with this r[B] and args r[B+1] ... r[B+C]
    case callSpread          // acc = r[A] called with this r[B] and the array r[C] as arguments
    case callEval            // like call, but a direct eval if r[A] is the realm's eval
    case construct           // acc = new r[A](r[B] ... r[B+C-1]), new.target r[A]
    case constructSpread     // acc = new r[A](...array r[B])
    case superCall           // acc = super(r[B] ... r[B+C-1]); binds this
    case superCallSpread     // acc = super(...array r[B])
    case superCallForward    // a default derived constructor: super(...arguments) without iterating

    // Literals.
    case createObject
    case createArray
    case arrayPush           // push acc onto the array r[A]
    case arrayHole           // push a hole onto r[A]
    case arraySpread         // push acc's iterated values onto r[A]
    case createRegExp        // acc = new RegExp(constant A, flags constant B)
    case createClosure       // acc = a closure of function constant A
    case getTemplateObject   // acc = the template object of constant A

    // Classes.
    case createClass         // acc = constructor of function constant A with heritage r[B] (B = -1: no extends; r[B] = null allowed); r[C] = the prototype
    case addField            // record an instance field on class r[A]: key r[B], initializer r[C] (or -1)
    case addPrivateMethod    // record private method acc named r[B] on class r[A]; C: 0 method, 1 getter, 2 setter
    case addStaticPrivateMethod // install private method acc named r[B] on r[A] now; C as above
    case initFields          // run the running class constructor's field initializers on this
    case newPrivateName      // acc = a new private name, described by constant A

    // Iteration.
    case getIterator         // r[A] = iterator of acc, r[A+1] = its next method, r[A+2] = done
    case getAsyncIterator    // same, for for-await and yield* in async generators
    case iteratorStep        // call r[A+1] on r[A]; if done, set r[A+2] and jump to B; else acc = value
    case iteratorNext        // acc = the result of calling r[A+1] on r[A] with acc (unchecked)
    case iteratorResult      // acc must be an object: if done, set r[A+2] and jump to B, else acc = value
    case iteratorClose       // IteratorClose r[A] for a normal completion (if not done)
    case iteratorCloseThrow  // IteratorClose r[A] for a throw completion: errors from return are dropped
    case asyncIteratorClose  // acc = the awaitable result of calling return on r[A], or undefined; jumps to B if there is no return method
    case iteratorToArray     // acc = an array of the remaining values of iterator r[A]
    case forInPrepare        // r[A] = a for-in enumerator of acc
    case forInNext           // acc = the next key of enumerator r[A], or jump to B

    // Generators and async functions.
    case generatorStart      // suspend at the start: the call returns the generator object
    case yieldOp             // suspend with acc; on resume r[A] = mode (0 next, 1 throw, 2 return), r[B] = the value sent
    case awaitOp             // suspend until acc settles: acc = its value, or throw its reason
    case asyncReturnAwait    // for return in an async generator: await acc before returning

    // Explicit resource management (ES2026).
    case createDisposeScope  // r[A] = a new dispose capability
    case addDisposable       // add acc (using x = acc) to r[A]'s resources; B is 1 for await using
    case disposeNext         // dispose r[A]'s newest resource: acc = 0 when none are left, 1 when disposed, 2 when r[B] is to be awaited
    case disposeError        // record acc as thrown in r[A]'s scope (combined as SuppressedError)
    case disposeFinish       // throw the error r[A] recorded, if any

    // Modules.
    case importCall          // acc = import(acc)
    case importMeta

    case nop
}

/// Instruction is one operation and its operands.
public struct Instruction {
    public var Op: Opcode
    public var A: int32
    public var B: int32
    public var C: int32

    public init(_ op: Opcode, _ a: int32 = 0, _ b: int32 = 0, _ c: int32 = 0) {
        self.Op = op
        self.A = a
        self.B = b
        self.C = c
    }
}

/// TemplateInfo is a tagged template call site's strings.
public final class TemplateInfo {
    public let Cooked: [str.JSString?]
    public let Raw: [str.JSString]
    /// ID identifies the call site, for the realm's template cache.
    public let ID: int
    public init(cooked: [str.JSString?], raw: [str.JSString]) {
        self.Cooked = cooked
        self.Raw = raw
        self.ID = nextTemplateID
        nextTemplateID += 1
    }
}

var nextTemplateID: int = 1

/// GlobalDecls is what a script declares at its top level, for
/// GlobalDeclarationInstantiation.
public final class GlobalDecls {
    public var VarNames: [str.JSString] = []
    public var FunctionNames: [str.JSString] = []
    public var LexNames: [str.JSString] = []
    public var ConstNames: [str.JSString] = []
    /// IsEval makes vars configurable, as eval's are.
    public var IsEval: bool = false
    public init() {}
}

/// Constant is one entry of a function's constant pool.
public enum Constant {
    case number(float64)
    case string(str.JSString)
    case key(value.PropertyKey)
    case bigint(value.BigInt)
    case function(FunctionTemplate)
    case template(TemplateInfo)
    case globals(GlobalDecls)
}

/// Handler is one entry of the exception table: a throw from an
/// instruction in [Start, End) goes to Target with the exception in the
/// accumulator. A finally handler also records its completion registers,
/// so a generator's return can run it: the interpreter sets r[KindReg] to 2
/// and r[ValueReg] to the value, and jumps to FinallyStart.
public struct Handler {
    public var Start: int
    public var End: int
    public var Target: int
    public var IsFinally: bool
    public var KindReg: int
    public var ValueReg: int
    public var FinallyStart: int
    /// ContextDepth is how many contexts the handler's code expects above
    /// the function's own: the interpreter pops the rest.
    public var ContextDepth: int

    public init(start: int, end: int, target: int, isFinally: bool, kindReg: int = -1, valueReg: int = -1, finallyStart: int = -1, contextDepth: int = 0) {
        self.Start = start
        self.End = end
        self.Target = target
        self.IsFinally = isFinally
        self.KindReg = kindReg
        self.ValueReg = valueReg
        self.FinallyStart = finallyStart
        self.ContextDepth = contextDepth
    }
}

/// ScopeInfo names the slots of a context, so that eval and with can find
/// bindings by name at runtime.
public final class ScopeInfo {
    public var Names: [str.JSString] = []
    public var Const: [bool] = []
    /// Lexical marks let, const and class slots, which a sloppy eval's var
    /// may not redeclare.
    public var Lexical: [bool] = []
    /// IsFunctionScope marks the context that holds a function's vars:
    /// where a sloppy eval's vars go.
    public var IsFunctionScope: bool = false
    public init() {}

    public func Find(_ name: str.JSString) -> int {
        var i = 0
        while i < Names.count {
            if Names[i].Equals(name) { return i }
            i += 1
        }
        return -1
    }
}

public enum FunctionKind: Equatable {
    case normal
    case arrow
    case method
    case getter
    case setter
    case classConstructor
    case derivedConstructor
    case classFieldInit
    case staticBlock
    case script
    case module
    case eval
}

/// FunctionTemplate is a compiled function: code plus everything a
/// closure of it needs.
public final class FunctionTemplate {
    public var Name: str.JSString
    public var Kind: FunctionKind
    public var Code: [Instruction] = []
    public var Constants: [Constant] = []
    public var Handlers: [Handler] = []
    public var Scopes: [ScopeInfo] = []
    /// FunctionScope is the index in Scopes of the function's own context,
    /// made at entry, or -1 when it needs none.
    public var FunctionScope: int = -1
    public var FunctionContextSlots: int = 0
    public var RegisterCount: int = 0
    /// Length is the function's "length": parameters before the first
    /// default or rest.
    public var Length: int = 0
    public var ParamCount: int = 0
    public var Strict: bool = false
    public var IsAsync: bool = false
    public var IsGenerator: bool = false
    /// NeedsFunctionEnv is set when arrows or eval inside read this,
    /// new.target or super, so the frame's must be shared.
    public var NeedsFunctionEnv: bool = false
    public var IsDefaultDerivedConstructor: bool = false
    /// HasFields marks a class constructor whose class has instance
    /// fields or private methods.
    public var IsClassFieldInit: bool = false
    /// Source, Start and End give the function's source text, for
    /// toString; Filename and Line, for stack traces.
    public var Source: SourceText? = nil
    public var Start: int = 0
    public var End: int = 0
    public var Line: int = 0
    /// Lines maps instruction indexes to source lines: pairs of (pc, line).
    public var Lines: [int] = []
    /// CalleeText renders the callee of the call or new at an instruction,
    /// for "x is not a function".
    public var CalleeText: [int: string] = [:]
    /// MappedParams gives, per parameter, the function context slot a
    /// sloppy mapped arguments object aliases (-1 for none).
    public var MappedParams: [int] = []

    public init(name: str.JSString, kind: FunctionKind) {
        self.Name = name
        self.Kind = kind
    }

    public var IsArrow: bool { return Kind == .arrow }

    public var IsClassConstructor: bool {
        return Kind == .classConstructor || Kind == .derivedConstructor
    }

    /// IsConstructor: ordinary functions and class constructors.
    public var IsConstructor: bool {
        if IsAsync || IsGenerator { return false }
        return Kind == .normal || Kind == .classConstructor || Kind == .derivedConstructor
    }

    /// LineAt is the source line of the instruction at pc.
    public func LineAt(_ pc: int) -> int {
        var line = Line
        var i = 0
        while i + 1 < Lines.count {
            if Lines[i] > pc { break }
            line = Lines[i + 1]
            i += 2
        }
        return line
    }

    /// SourceText is the function's source, for Function.prototype.toString.
    public var SourceString: string {
        guard let s = Source, !s.Hidden else { return "" }
        return s.Slice(Start, End)
    }
}

/// SourceText is a script's text, shared by its functions.
public final class SourceText {
    /// Hidden is set on a built-in's self-hosted source: its functions
    /// show [native code], as native ones do.
    public var Hidden: bool = false
    public let Filename: string
    public let Bytes: [uint8]

    public init(filename: string, text: string) {
        self.Filename = filename
        self.Bytes = [uint8](text.utf8)
    }

    public func Slice(_ start: int, _ end: int) -> string {
        if start >= end || start < 0 { return "" }
        var b: [uint8] = []
        var i = start
        while i < end && i < Bytes.count { b.append(Bytes[i]); i += 1 }
        return string(decoding: b, as: UTF8.self)
    }
}

/// Disassemble prints a function and the functions nested in it.
public func Disassemble(_ fn: FunctionTemplate) -> string {
    var out = ""
    disassemble(fn, &out)
    return out
}

func disassemble(_ fn: FunctionTemplate, _ out: inout string) {
    out += "== \(fn.Name.String.isEmpty ? "<anonymous>" : fn.Name.String) (\(fn.Kind)) registers \(fn.RegisterCount), params \(fn.ParamCount)"
    if fn.FunctionScope >= 0 { out += ", context \(fn.FunctionContextSlots)" }
    out += "\n"
    var i = 0
    while i < fn.Code.count {
        let ins = fn.Code[i]
        var num = "\(i)"
        while num.count < 4 { num = " " + num }
        out += num + "  \(ins.Op)"
        switch ins.Op {
        case .ldaConst, .getTemplateObject, .createClosure, .ldaGlobal, .ldaGlobalTypeof, .ldaLookup, .ldaLookupTypeof, .deleteLookup:
            out += " " + constString(fn, int(ins.A))
        case .getNamed, .setNamed, .defineNamed:
            out += " r\(ins.A) " + constString(fn, int(ins.B))
        default:
            out += " \(ins.A) \(ins.B) \(ins.C)"
        }
        out += "\n"
        i += 1
    }
    for h in fn.Handlers {
        out += "  handler [\(h.Start), \(h.End)) -> \(h.Target)\(h.IsFinally ? " finally" : "")\n"
    }
    for c in fn.Constants {
        if case .function(let f) = c { disassemble(f, &out) }
    }
}

func constString(_ fn: FunctionTemplate, _ i: int) -> string {
    if i < 0 || i >= fn.Constants.count { return "?" }
    switch fn.Constants[i] {
    case .number(let d): return "\(d)"
    case .string(let s): return "\"\(s.String)\""
    case .key(let k): return k.Debug
    case .bigint(let b): return b.ToString(10) + "n"
    case .function(let f): return "<function \(f.Name.String)>"
    case .template: return "<template>"
    case .globals: return "<globals>"
    }
}
