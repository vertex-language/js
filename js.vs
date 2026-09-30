// Package js is the JavaScript engine's embedding API: a Runtime is an
// agent with one realm, every built-in installed, that evaluates scripts
// and runs their jobs. Hosts (vjs, a web view) add their own globals --
// console, timers, the DOM -- on top.
package js

import (
    "js/builtin/control"
    "js/builtin/fundamental"
    "js/builtin/global"
    "js/builtin/indexed"
    "js/builtin/keyed"
    "js/builtin/memory"
    "js/builtin/numeric"
    "js/builtin/reflection"
    "js/builtin/structured"
    "js/builtin/text"
    "js/bytecode"
    "js/codegen"
    "js/interp"
    "js/object"
    "js/parser"
    "js/scope"
    "js/str"
    "js/value"
)

/// Exception is a JavaScript exception that reached the host: the thrown
/// value, and its message and stack as V8 would print them.
public struct Exception: Error, CustomStringConvertible {
    public let Value: object.Value

    public init(_ v: object.Value) {
        self.Value = v
    }

    /// Message is `Name: message` for an error object, or the value as a
    /// string.
    public var Message: string {
        if case .object(let o) = Value, o.Kind == .error {
            let n = (try? o.Get(value.PropertyKey.Named("name"), Value)) ?? .undefined
            let m = (try? o.Get(value.PropertyKey.Named("message"), Value)) ?? .undefined
            let name = n.IsUndefined ? "Error" : ((try? object.ToString(n).String) ?? "Error")
            let msg = m.IsUndefined ? "" : ((try? object.ToString(m).String) ?? "")
            return msg.isEmpty ? name : name + ": " + msg
        }
        return (try? object.ToString(Value).String) ?? object.Describe(Value)
    }

    /// Stack is the error's stack property, when it has one.
    public var Stack: string {
        if case .object(let o) = Value, let s = try? o.Get(value.PropertyKey.Named("stack"), Value), case .string(let ss) = s {
            return ss.String
        }
        return Message
    }

    public var description: string { return Message }
}

/// Runtime is an agent and its realm, with the interpreter installed.
public final class Runtime {
    public let Agent: object.Agent
    public let Realm: object.Realm
    public let Engine: interp.Engine

    public init() {
        Agent = object.Agent()
        Realm = object.Realm(agent: Agent)
        Engine = interp.Engine()
        object.SetCurrentRealm(Realm)
        Engine.Install(Realm)
        fundamental.Install(Realm)
        global.Install(Realm)
        indexed.Install(Realm)
        control.Install(Realm)
        numeric.Install(Realm)
        text.Install(Realm)
        keyed.Install(Realm)
        reflection.Install(Realm)
        structured.Install(Realm)
        memory.Install(Realm)
        installHostBasics()
    }

    /// installHostBasics defines what every JavaScript host has, though
    /// ECMA-262 leaves it to the host: queueMicrotask (HTML's
    /// WindowOrWorkerGlobalScope), which queues a job on the agent's
    /// microtask queue.
    func installHostBasics() {
        let agent = Agent
        let queue = Realm.Function("queueMicrotask", 1) { _, args, _ in
            let cb: object.Value = args.count > 0 ? args[0] : .undefined
            guard case .object(let fn) = cb, fn.IsCallable else {
                throw object.ThrowTypeError("Failed to execute 'queueMicrotask': parameter 1 is not of type 'Function'.")
            }
            agent.Enqueue {
                _ = try fn.Call(.undefined, [])
            }
            return .undefined
        }
        Define("queueMicrotask", .object(queue))
    }

    /// Global is the global object.
    public var Global: object.JSObject { return Realm.Global }

    /// Compile parses and compiles a script without running it; a syntax
    /// error is thrown as the SyntaxError object a script would see.
    public func Compile(_ source: string, filename: string = "<eval>") throws -> bytecode.FunctionTemplate {
        do {
            do {
                let prog = try parser.ParseScript(source, filename: filename)
                _ = try scope.Analyze(prog)
                return try codegen.CompileScript(prog, source: bytecode.SourceText(filename: filename, text: source))
            } catch let e as parser.ParseError {
                throw object.ThrowSyntaxError(e.Message)
            } catch let e as scope.ScopeError {
                throw object.ThrowSyntaxError(e.Message)
            } catch let e as codegen.CompileError {
                throw object.ThrowSyntaxError(e.Message)
            }
        } catch let c as object.Completion {
            throw Exception(c.Value)
        }
    }

    /// Evaluate runs a script and returns its completion value. It does
    /// not run the jobs the script queued; RunJobs does.
    public func Evaluate(_ source: string, filename: string = "<eval>") throws -> object.Value {
        let t = try Compile(source, filename: filename)
        object.SetCurrentRealm(Realm)
        do {
            return try Engine.RunScript(t, realm: Realm)
        } catch let c as object.Completion {
            throw Exception(c.Value)
        }
    }

    /// RunJobs runs promise jobs until none are left.
    public func RunJobs() {
        object.SetCurrentRealm(Realm)
        Agent.RunJobs()
    }

    /// HasJobs says promise jobs are waiting.
    public var HasJobs: bool { return Agent.HasJobs }

    /// Call calls a function value, turning a throw into an Exception.
    public func Call(_ f: object.Value, this: object.Value = .undefined, _ args: [object.Value]) throws -> object.Value {
        object.SetCurrentRealm(Realm)
        do {
            return try object.Call(f, this, args)
        } catch let c as object.Completion {
            throw Exception(c.Value)
        }
    }

    /// Define makes a global property, as a host's globals are made:
    /// writable, configurable, and not enumerable.
    public func Define(_ name: string, _ v: object.Value) {
        Realm.DefineGlobal(name, v)
    }

    /// Function makes a built-in function the host implements.
    public func Function(_ name: string, _ length: int, _ fn: @escaping object.NativeFn) -> object.NativeFunction {
        return Realm.Function(name, length, fn)
    }

    /// DefineConsole defines a console whose log, info, warn, error and
    /// debug join their arguments' strings with spaces and hand the line
    /// to write. A host decides where it goes: a terminal, a devtools pane.
    public func DefineConsole(_ write: @escaping (string) -> Void) {
        let console = object.JSObject(proto: Realm.ObjectPrototype)
        for name in ["log", "info", "warn", "error", "debug"] {
            let fn = Function(name, 0) { _, args, _ in
                var parts: [string] = []
                for v in args { parts.append((try? object.ToString(v).String) ?? object.Describe(v)) }
                write(parts.joined(separator: " "))
                return .undefined
            }
            console.DefineData(object.Key(name), .object(fn), writable: true, enumerable: true, configurable: true)
        }
        Define("console", .object(console))
    }

    /// String makes a JavaScript string value.
    public func StringValue(_ s: string) -> object.Value {
        return .string(str.JSString.From(s))
    }
}
