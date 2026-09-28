package js

import (
    "gc"
    "js/token"
    "js/scanner"
    "js/ast"
    "js/parser"
    "js/scope"
    "js/printer"
    "js/bytecode"
    "js/codegen"
    "js/value"
    "js/str"
    "js/object"
    "js/ic"
    "js/interp"
    "js/builtin/global"
    "js/builtin/fundamental"
    "js/builtin/numeric"
    "js/builtin/text"
    "js/builtin/indexed"
    "js/builtin/keyed"
    "js/builtin/structured"
    "js/builtin/memory"
    "js/regexp"
)

public typealias Value = value.Value
public typealias JSObject = object.JSObject
public typealias JSString = str.JSString
public typealias Cell = gc.Cell
public typealias Heap = gc.Heap
public typealias Tracer = gc.Tracer
public typealias ObjectHandle = gc.Handle<JSObject>
public typealias HandleScope = gc.HandleScope

/// Exception models a JavaScript runtime or compilation error surfaced to the host.
public struct Exception: Error, CustomStringConvertible {
    public let Message: string
    public let Stack: string

    public init(message: string, stack: string = "") {
        self.Message = message
        self.Stack = stack
    }

    public var description: string {
        if Stack.isEmpty { return Message }
        return "\(Message)\n\(Stack)"
    }
}

/// Realm represents an execution context with its own global object and built-in intrinsics.
public final class Realm {
    public let Inner: object.Realm
    public let VM: interp.VM

    public init(inner: object.Realm? = nil) {
        let r = inner ?? object.Realm()
        self.Inner = r
        let vm = interp.VM()
        self.VM = vm

        // Connect VM execution stack with Realm Heap roots
        r.Heap.Roots.AddProvider { [weak vm] in
            guard let v = vm else { return [] }
            return v.CollectRoots()
        }

        // Register built-in packages into the realm
        global.Register(into: r)
        fundamental.Register(into: r)
        numeric.Register(into: r)
        text.Register(into: r)
        indexed.Register(into: r)
        keyed.Register(into: r)
        structured.Register(into: r)
        memory.Register(into: r)
    }

    public var Heap: gc.Heap {
        return Inner.Heap
    }

    /// GC triggers an explicit garbage collection pass across all heap objects.
    public func GC() {
        Inner.Heap.Collect()
    }

    public var Global: object.JSObject {
        return Inner.GlobalObject
    }

    /// NewObject creates a new JavaScript object associated with this realm.
    public func NewObject() -> object.JSObject {
        return Inner.NewObject()
    }

    /// NewArray creates a new JavaScript array object associated with this realm.
    public func NewArray(elements: [value.Value] = []) -> object.JSObject {
        return Inner.NewArray(elements: elements)
    }

    /// DefineFunction exposes a native host function to this Realm's global scope.
    public func DefineFunction(_ name: string, _ callback: @escaping ([value.Value]) throws -> value.Value) {
        let fn = Inner.NewFunction(name: name) { _, _, args in
            return try callback(args)
        }
        Global.Set(name, value.Value.Object(fn))
    }

    /// Eval parses, compiles, and evaluates JavaScript source code.
    public func Eval(_ source: string, filename: string = "<eval>") throws -> value.Value {
        do {
            let prog = try parser.ParseScript(source, filename: filename)
            let code = try codegen.Compile(prog)
            return try VM.Run(code, realm: Inner)
        } catch let parseErr as parser.ParseError {
            throw Exception(message: parseErr.description)
        } catch let scopeErr as scope.ScopeError {
            throw Exception(message: scopeErr.description)
        } catch let vmErr as interp.VMError {
            throw Exception(message: vmErr.description)
        } catch {
            throw Exception(message: "Evaluation failed: \(error)")
        }
    }

    /// Call invokes a callable JavaScript Value with a this-argument and parameters.
    public func Call(_ fnVal: value.Value, thisArg: value.Value = value.Value.Undefined, args: [value.Value] = []) throws -> value.Value {
        guard let obj = fnVal.ObjVal as? object.JSObject, let callable = obj.Callable else {
            throw Exception(message: "TypeError: \(fnVal) is not a function")
        }
        switch callable {
        case .native(let cb):
            return try cb(Inner, thisArg, args)
        case .bytecode(let code):
            return try VM.Run(code, realm: Inner, thisValue: thisArg, args: args)
        }
    }
}

/// Agent coordinates execution contexts, the job queue, and hosts.
public final class Agent {
    var jobQueue: [() -> Void] = []
    public var DefaultRealm: Realm

    public init() {
        self.DefaultRealm = Realm()
    }

    /// NewRealm creates a new isolated Realm within this Agent.
    public func NewRealm() -> Realm {
        return Realm()
    }

    /// EnqueueJob schedules a microtask to be run in the agent.
    public func EnqueueJob(_ job: @escaping () -> Void) {
        jobQueue.append(job)
    }

    /// RunJobs empties the microtask queue.
    public func RunJobs() {
        while !jobQueue.isEmpty {
            let job = jobQueue.removeFirst()
            job()
        }
    }
}

/// Global convenience evaluation in a default agent realm.
public func Eval(_ source: string) throws -> value.Value {
    let agent = Agent()
    return try agent.DefaultRealm.Eval(source)
}
