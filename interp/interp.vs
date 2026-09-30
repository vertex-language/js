// Package interp runs js/bytecode: the Engine behind every realm's
// ECMAScript function objects.
//
// A call runs a Frame: registers, an accumulator, the current context and
// the program counter. Generators and async functions keep their frame
// when they suspend at a yield or an await, and resume it later; the
// frame is all the state there is.
package interp

import (
    "js/bytecode"
    "js/object"
    "js/str"
    "js/value"
)

typealias Value = object.Value

/// Exit is how a frame's run ended for now.
enum Exit {
    case returned(Value)
    case yielded(Value, bool)   // the value, and whether it is already an iterator result
    case awaited(Value)
    case started                // a generator at its start
    case call(Frame)            // a call to run on the frame stack; the caller resumes with its value
}

/// Frame is one activation of a function, script or eval.
final class Frame {
    let t: bytecode.FunctionTemplate
    let fn: object.JSFunction?
    var regs: [Value]
    let args: [Value]
    var pc: int = 0
    var acc: Value = .undefined
    var ctx: object.Context?
    /// ctxDepth counts contexts pushed beyond the function's own.
    var ctxDepth: int = 0
    var this: Value
    var newTarget: Value
    var funcEnv: object.FunctionEnv?
    let realm: object.Realm
    /// varContext is where a sloppy direct eval's vars go (nil: global).
    var varContext: object.Context? = nil
    var isEval: bool = false
    var yieldModeReg: int32 = -1
    var yieldValueReg: int32 = -1
    /// generator is the object a generatorStart returns.
    var generator: object.JSObject? = nil
    /// constructed is the object a [[Construct]] run on the frame stack
    /// made, which the frame's return value may replace.
    var constructed: object.JSObject? = nil

    init(t: bytecode.FunctionTemplate, fn: object.JSFunction?, args: [Value], this: Value, newTarget: Value, ctx: object.Context?, realm: object.Realm) {
        self.t = t
        self.fn = fn
        self.args = args
        self.this = this
        self.newTarget = newTarget
        self.ctx = ctx
        self.realm = realm
        self.regs = [Value](repeating: .undefined, count: t.RegisterCount)
    }
}

/// Engine runs bytecode for every realm of an agent.
public final class Engine: object.Engine {
    var frames: [Frame] = []
    var depth: int = 0
    /// MaxDepth bounds JavaScript call depth ("Maximum call stack size exceeded").
    public var MaxDepth: int = 10000
    /// StackLimit bounds the native stack, in bytes, the engine uses below
    /// where it was entered. JavaScript-to-JavaScript calls use none; a
    /// built-in calling back into JavaScript uses a few kilobytes. A host
    /// running the engine on a thread with a small stack lowers it; one on
    /// a main thread's 8 MB can raise it.
    public var StackLimit: int = 1 << 20
    var stackBase: uint = 0

    public init() {}

    // MARK: running

    /// run executes a frame until it returns, yields, awaits or starts, and
    /// dispatches exceptions to its handlers. throwing resumes the frame by
    /// throwing at its current instruction (an await's rejection).
    ///
    /// Calls from bytecode to ordinary bytecode functions do not recurse:
    /// exec hands back the callee's frame, run pushes it, and the caller
    /// resumes with its return value. An exception no handler in a frame
    /// catches pops that frame and is thrown again at the caller's call.
    func run(_ base: Frame, throwing: Value? = nil) throws -> Exit {
        // Built-ins that call back into JavaScript (map, getters, toString)
        // still nest run on the native stack: bound the bytes that uses.
        let sp = stackAddress()
        if frames.isEmpty {
            stackBase = sp
        } else if stackBase > sp && stackBase - sp > uint(StackLimit) {
            throw object.ThrowRangeError("Maximum call stack size exceeded")
        }
        let bottom = frames.count
        frames.append(base)
        let savedRealm = object.CurrentRealmOrNil()
        object.SetCurrentRealm(base.realm)
        defer {
            depth -= frames.count - bottom - 1
            while frames.count > bottom { _ = frames.removeLast() }
            object.SetCurrentRealm(savedRealm)
        }
        var pending = throwing
        while true {
            let f = frames[frames.count - 1]
            do {
                if let err = pending {
                    pending = nil
                    throw object.Completion(err)
                }
                let exit = try exec(f)
                switch exit {
                case .call(let callee):
                    if depth >= MaxDepth {
                        f.pc -= 1
                        throw object.ThrowRangeError("Maximum call stack size exceeded")
                    }
                    depth += 1
                    frames.append(callee)
                    object.SetCurrentRealm(callee.realm)
                case .returned(let v):
                    if frames.count - 1 == bottom { return exit }
                    let done = frames.removeLast()
                    depth -= 1
                    let caller = frames[frames.count - 1]
                    object.SetCurrentRealm(caller.realm)
                    if let obj = done.constructed {
                        if v.IsObject {
                            caller.acc = v
                        } else if done.t.IsClassConstructor && !v.IsUndefined {
                            caller.pc -= 1
                            throw object.ThrowTypeError("Class constructors may only return object or undefined")
                        } else {
                            caller.acc = .object(obj)
                        }
                    } else {
                        caller.acc = v
                    }
                default:
                    return exit
                }
            } catch let c as object.Completion {
                var cur = frames[frames.count - 1]
                while true {
                    if let h = findHandler(cur) {
                        while cur.ctxDepth > h.ContextDepth {
                            cur.ctx = cur.ctx?.Parent
                            cur.ctxDepth -= 1
                        }
                        cur.acc = c.Value
                        cur.pc = h.Target
                        break
                    }
                    if frames.count - 1 == bottom { throw c }
                    _ = frames.removeLast()
                    depth -= 1
                    cur = frames[frames.count - 1]
                    // Back to the call instruction, for its handler.
                    cur.pc -= 1
                    object.SetCurrentRealm(cur.realm)
                }
            }
        }
    }

    func findHandler(_ f: Frame) -> bytecode.Handler? {
        let pc = f.pc
        for h in f.t.Handlers {
            if pc >= h.Start && pc < h.End { return h }
        }
        return nil
    }

    /// complete runs a frame that must return.
    func complete(_ f: Frame) throws -> Value {
        switch try run(f) {
        case .returned(let v): return v
        default: return .undefined
        }
    }

    // MARK: object.Engine

    public func CallFunction(_ fn: object.JSFunction, _ this: Value, _ args: [Value]) throws -> Value {
        let t = fn.Template
        depth += 1
        defer { depth -= 1 }
        if depth > MaxDepth {
            throw object.ThrowRangeError("Maximum call stack size exceeded")
        }
        let f = makeFrame(fn, this: thisFor(fn, this), args: args, newTarget: .undefined)
        if t.IsGenerator {
            return try startGenerator(f, async: t.IsAsync)
        }
        if t.IsAsync {
            return try startAsync(f)
        }
        return try complete(f)
    }

    public func ConstructFunction(_ fn: object.JSFunction, _ args: [Value], _ newTarget: object.JSObject) throws -> Value {
        let t = fn.Template
        depth += 1
        defer { depth -= 1 }
        if depth > MaxDepth {
            throw object.ThrowRangeError("Maximum call stack size exceeded")
        }
        if t.Kind == .derivedConstructor {
            let f = makeFrame(fn, this: .empty, args: args, newTarget: .object(newTarget))
            let r = try complete(f)
            if r.IsObject { return r }
            if !r.IsUndefined {
                throw object.ThrowTypeError("Derived constructors may only return object or undefined")
            }
            let thisV = f.funcEnv!.This
            if thisV.IsEmpty {
                throw object.ThrowReferenceError("Must call super constructor in derived class before accessing 'this' or returning from derived constructor")
            }
            return thisV
        }
        let proto = try object.GetPrototypeFromConstructor(newTarget, fn.Realm.ObjectPrototype)
        let obj = object.JSObject(proto: proto)
        if t.IsClassConstructor {
            try initializeInstanceElements(obj, fn)
        }
        let f = makeFrame(fn, this: .object(obj), args: args, newTarget: .object(newTarget))
        let r = try complete(f)
        if r.IsObject { return r }
        if t.IsClassConstructor && !r.IsUndefined {
            throw object.ThrowTypeError("Class constructors may only return object or undefined")
        }
        return .object(obj)
    }

    public func StackTrace() -> string {
        var out = ""
        var i = frames.count - 1
        var n = 0
        while i >= 0 && n < 10 {
            let f = frames[i]
            let t = f.t
            var name = t.Name.String
            if name.isEmpty {
                name = t.Kind == .script || t.Kind == .eval ? "" : "<anonymous>"
            }
            let file = t.Source?.Filename ?? ""
            let line = t.LineAt(f.pc)
            if !out.isEmpty { out += "\n" }
            if name.isEmpty {
                out += "    at \(file):\(line)"
            } else {
                out += "    at \(name) (\(file):\(line))"
            }
            i -= 1
            n += 1
        }
        return out
    }

    // MARK: frames

    /// thisFor is OrdinaryCallBindThis's this: a sloppy function sees the
    /// global object for null and undefined, and wrappers for primitives.
    func thisFor(_ fn: object.JSFunction, _ this: Value) -> Value {
        let t = fn.Template
        if t.Strict || t.IsArrow { return this }
        switch this {
        case .undefined, .null, .empty:
            return .object(fn.Realm.Global)
        case .object:
            return this
        default:
            if let o = try? object.ToObject(this) { return .object(o) }
            return this
        }
    }

    func makeFrame(_ fn: object.JSFunction, this: Value, args: [Value], newTarget: Value) -> Frame {
        let t = fn.Template
        var ctx = fn.Env
        if t.FunctionScope >= 0 {
            ctx = object.Context(slots: t.FunctionContextSlots, parent: fn.Env, info: t.Scopes[t.FunctionScope])
        }
        let f = Frame(t: t, fn: fn, args: args, this: this, newTarget: newTarget, ctx: ctx, realm: fn.Realm)
        if t.IsArrow {
            f.funcEnv = fn.FuncEnv
            if let fe = fn.FuncEnv {
                f.this = fe.This
                f.newTarget = fe.NewTarget
            }
        } else if t.NeedsFunctionEnv {
            f.funcEnv = object.FunctionEnv(this: this, newTarget: newTarget, function: fn)
        }
        return f
    }

    /// funcEnvOf gives a frame a function environment for an arrow created
    /// in it, making one if the frame has none yet.
    func funcEnvOf(_ f: Frame) -> object.FunctionEnv {
        if let fe = f.funcEnv { return fe }
        let fe = object.FunctionEnv(this: f.this, newTarget: f.newTarget, function: f.fn)
        f.funcEnv = fe
        return fe
    }

    /// thisOf is the frame's this binding, checked in derived constructors.
    func thisOf(_ f: Frame) throws -> Value {
        if let fe = f.funcEnv {
            if fe.This.IsEmpty {
                throw object.ThrowReferenceError("Must call super constructor in derived class before accessing 'this' or returning from derived constructor")
            }
            return fe.This
        }
        return f.this
    }

    /// activeFunction is the non-arrow function whose code is running:
    /// the one super and new.target refer to.
    func activeFunction(_ f: Frame) -> object.JSFunction? {
        if let fe = f.funcEnv, let fn = fe.Function { return fn }
        return f.fn
    }

    // MARK: classes

    /// initializeInstanceElements is §7.3.34: private methods, then fields.
    func initializeInstanceElements(_ obj: object.JSObject, _ ctor: object.JSFunction) throws {
        for m in ctor.PrivateMethods {
            if obj.PrivateFind(m.Name) >= 0 {
                throw object.ThrowTypeError("Cannot initialize private methods of class \(ctor.Template.Name.String) twice on the same object")
            }
            installPrivateMethod(obj, m)
        }
        for field in ctor.Fields {
            var v: Value = .undefined
            if let initFn = field.Initializer {
                v = try initFn.Call(.object(obj), [])
            }
            if field.Key.IsPrivate {
                if obj.find(field.Key) >= 0 {
                    throw object.ThrowTypeError("Cannot initialize \(field.Key.Debug) twice on the same object")
                }
                obj.store(field.Key, object.Slot(value: v, flags: 1))
            } else {
                try object.CreateDataPropertyOrThrow(obj, field.Key, v)
            }
        }
    }

    func installPrivateMethod(_ obj: object.JSObject, _ m: object.PrivateMethod) {
        let key = value.PropertyKey.symbol(m.Name)
        if let fn = m.Method {
            obj.store(key, object.Slot(value: .object(fn), flags: 0))
        } else {
            var s = object.Slot(value: .undefined, flags: 8)
            s.Getter = m.Getter
            s.Setter = m.Setter
            obj.store(key, s)
        }
    }

    // MARK: calls

    /// inlineCallee is the callee when a call can run on the frame stack:
    /// an ordinary bytecode function of this engine (not a generator, an
    /// async function, or a class constructor, which throws).
    func inlineCallee(_ callee: Value) -> object.JSFunction? {
        guard case .object(let o) = callee, let fn = o as? object.JSFunction else { return nil }
        let t = fn.Template
        if t.IsGenerator || t.IsAsync || t.IsClassConstructor { return nil }
        guard let e = fn.Realm.Engine, e === self else { return nil }
        return fn
    }

    /// inlineConstruct is the frame for `new callee(...args)` when it can run
    /// on the frame stack: an ordinary function or base class constructor
    /// of this engine. Derived constructors, whose this comes from super,
    /// take the native path.
    func inlineConstruct(_ callee: Value, _ args: [Value]) throws -> Frame? {
        guard case .object(let o) = callee, let fn = o as? object.JSFunction, fn.IsConstructor else { return nil }
        let t = fn.Template
        if t.Kind == .derivedConstructor { return nil }
        guard let e = fn.Realm.Engine, e === self else { return nil }
        let proto = try object.GetPrototypeFromConstructor(fn, fn.Realm.ObjectPrototype)
        let obj = object.JSObject(proto: proto)
        if t.IsClassConstructor {
            try initializeInstanceElements(obj, fn)
        }
        let f = makeFrame(fn, this: .object(obj), args: args, newTarget: .object(fn))
        f.constructed = obj
        return f
    }

    func callValue(_ f: Frame, _ callee: Value, _ this: Value, _ args: [Value]) throws -> Value {
        guard case .object(let o) = callee, o.IsCallable else {
            throw object.ThrowTypeError("\(calleeText(f)) is not a function")
        }
        return try o.Call(this, args)
    }

    func calleeText(_ f: Frame) -> string {
        if let s = f.t.CalleeText[f.pc] { return s }
        return "expression"
    }

    // MARK: running scripts

    /// RunScript compiles nothing: it runs a compiled script's template in a realm.
    public func RunScript(_ t: bytecode.FunctionTemplate, realm: object.Realm) throws -> Value {
        let f = Frame(t: t, fn: nil, args: [], this: .object(realm.Global), newTarget: .undefined, ctx: nil, realm: realm)
        return try complete(f)
    }
}

let emptyString = str.JSString.Empty

/// stackAddress is the address of a local: where the native stack is now.
func stackAddress() -> uint {
    var probe: int = 0
    return withUnsafeMutablePointer(to: &probe) { p in uint(bitPattern: p) }
}
