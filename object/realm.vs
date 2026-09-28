package object

import (
    "js/str"
    "js/value"
)

var currentRealmStorage: Realm? = nil

/// CurrentRealm is the realm of the running code (the spec's current
/// realm record). Built-ins and the interpreter set it as they run.
public func CurrentRealm() -> Realm {
    return currentRealmStorage!
}

public func SetCurrentRealm(_ r: Realm?) {
    currentRealmStorage = r
}

/// Job is a queued microtask (a promise reaction or a host job).
public typealias Job = () throws -> Void

/// Agent is the spec's agent: the job queue and the state shared by the
/// realms that run on one thread.
public final class Agent {
    var jobs: [Job] = []
    var jobHead: int = 0
    /// SymbolRegistry is Symbol.for's table.
    public var SymbolRegistry: [str.JSString: value.Symbol] = [:]
    /// OnUnhandledRejection is told of promises rejected with no handler,
    /// and of handlers added later (HostPromiseRejectionTracker).
    public var OnRejectionTracker: ((JSObject, bool) -> Void)? = nil
    /// OnUncaughtJobError is told of an exception thrown out of a job.
    public var OnJobError: ((Value) -> Void)? = nil
    /// KeptAlive holds WeakRef targets until the job queue drains (§9.9.1).
    public var KeptAlive: [JSObject] = []

    public init() {}

    public func Enqueue(_ job: @escaping Job) {
        jobs.append(job)
    }

    public var HasJobs: bool { return jobHead < jobs.count }

    /// RunJobs drains the microtask queue.
    public func RunJobs() {
        while jobHead < jobs.count {
            let job = jobs[jobHead]
            jobHead += 1
            if jobHead > 1024 && jobHead * 2 > jobs.count {
                jobs.removeFirst(jobHead)
                jobHead = 0
            }
            do {
                try job()
            } catch let c as Completion {
                if let h = OnJobError { h(c.Value) }
            } catch {
            }
        }
        jobs = []
        jobHead = 0
        KeptAlive = []
    }
}

/// GlobalBinding is a top-level let, const or class.
public final class GlobalBinding {
    public var Value: Value
    public let IsConst: bool
    public init(value: Value, isConst: bool) {
        self.Value = value
        self.IsConst = isConst
    }
}

/// Realm is a realm record (§9.3): a global object, its lexical
/// declarations, and the intrinsic objects.
public final class Realm {
    public let Agent: Agent
    public var Engine: Engine? = nil
    public var Global: JSObject
    public var GlobalLexicals: [str.JSString: GlobalBinding] = [:]
    /// TemplateMap caches tagged template objects per call site.
    public var TemplateMap: [int: JSObject] = [:]
    /// Intrinsics holds the intrinsics without a field of their own, by
    /// their spec names without the percent signs ("ThrowTypeError").
    public var Intrinsics: [string: JSObject] = [:]

    public let ObjectPrototype: JSObject
    public let FunctionPrototype: JSObject
    public var ArrayPrototype: JSObject
    public var ErrorPrototype: JSObject
    public var TypeErrorPrototype: JSObject
    public var RangeErrorPrototype: JSObject
    public var ReferenceErrorPrototype: JSObject
    public var SyntaxErrorPrototype: JSObject
    public var EvalErrorPrototype: JSObject
    public var URIErrorPrototype: JSObject
    public var AggregateErrorPrototype: JSObject
    public var StringPrototype: JSObject
    public var NumberPrototype: JSObject
    public var BooleanPrototype: JSObject
    public var SymbolPrototype: JSObject
    public var BigIntPrototype: JSObject
    public var IteratorPrototype: JSObject
    public var AsyncIteratorPrototype: JSObject
    public var ArrayIteratorPrototype: JSObject
    public var GeneratorPrototype: JSObject
    public var AsyncGeneratorPrototype: JSObject
    public var GeneratorFunctionPrototype: JSObject
    public var AsyncFunctionPrototype: JSObject
    public var AsyncGeneratorFunctionPrototype: JSObject
    public var AsyncFromSyncIteratorPrototype: JSObject
    public var PromisePrototype: JSObject
    public var RegExpPrototype: JSObject
    public var DatePrototype: JSObject
    public var MapPrototype: JSObject
    public var SetPrototype: JSObject

    public var ObjectConstructor: JSObject? = nil
    public var FunctionConstructor: JSObject? = nil
    public var ArrayConstructor: JSObject? = nil
    public var PromiseConstructor: JSObject? = nil
    public var RegExpConstructor: JSObject? = nil
    public var EvalFunction: JSObject? = nil
    public var ThrowTypeError: JSObject? = nil

    /// CreateRegExp is installed by the RegExp built-in so the interpreter
    /// can make regular expression literals.
    public var CreateRegExp: ((str.JSString, str.JSString) throws -> JSObject)? = nil

    public init(agent: Agent) {
        self.Agent = agent
        let op = JSObject(proto: nil)
        self.ObjectPrototype = op
        let fp = JSObject(proto: op)
        fp.Kind = .function
        self.FunctionPrototype = fp
        self.ArrayPrototype = JSObject(proto: op)
        self.ErrorPrototype = JSObject(proto: op)
        self.TypeErrorPrototype = JSObject(proto: op)
        self.RangeErrorPrototype = JSObject(proto: op)
        self.ReferenceErrorPrototype = JSObject(proto: op)
        self.SyntaxErrorPrototype = JSObject(proto: op)
        self.EvalErrorPrototype = JSObject(proto: op)
        self.URIErrorPrototype = JSObject(proto: op)
        self.AggregateErrorPrototype = JSObject(proto: op)
        self.StringPrototype = JSObject(proto: op)
        self.NumberPrototype = JSObject(proto: op)
        self.BooleanPrototype = JSObject(proto: op)
        self.SymbolPrototype = JSObject(proto: op)
        self.BigIntPrototype = JSObject(proto: op)
        self.IteratorPrototype = JSObject(proto: op)
        self.AsyncIteratorPrototype = JSObject(proto: op)
        self.ArrayIteratorPrototype = JSObject(proto: op)
        self.GeneratorPrototype = JSObject(proto: op)
        self.AsyncGeneratorPrototype = JSObject(proto: op)
        self.GeneratorFunctionPrototype = JSObject(proto: op)
        self.AsyncFunctionPrototype = JSObject(proto: op)
        self.AsyncGeneratorFunctionPrototype = JSObject(proto: op)
        self.AsyncFromSyncIteratorPrototype = JSObject(proto: op)
        self.PromisePrototype = JSObject(proto: op)
        self.RegExpPrototype = JSObject(proto: op)
        self.DatePrototype = JSObject(proto: op)
        self.MapPrototype = JSObject(proto: op)
        self.SetPrototype = JSObject(proto: op)
        let g = JSObject(proto: op)
        g.Kind = .global
        self.Global = g
        // Every error prototype but Error's inherits from Error.prototype.
        TypeErrorPrototype.Proto = ErrorPrototype
        RangeErrorPrototype.Proto = ErrorPrototype
        ReferenceErrorPrototype.Proto = ErrorPrototype
        SyntaxErrorPrototype.Proto = ErrorPrototype
        EvalErrorPrototype.Proto = ErrorPrototype
        URIErrorPrototype.Proto = ErrorPrototype
        AggregateErrorPrototype.Proto = ErrorPrototype
        ArrayIteratorPrototype.Proto = IteratorPrototype
        GeneratorPrototype.Proto = IteratorPrototype
        AsyncGeneratorPrototype.Proto = AsyncIteratorPrototype
        AsyncFromSyncIteratorPrototype.Proto = AsyncIteratorPrototype
        GeneratorFunctionPrototype.Proto = FunctionPrototype
        AsyncFunctionPrototype.Proto = FunctionPrototype
        AsyncGeneratorFunctionPrototype.Proto = FunctionPrototype
    }

    // MARK: helpers for built-ins

    /// Function makes a built-in function.
    public func Function(_ name: string, _ length: int, _ fn: @escaping NativeFn) -> NativeFunction {
        return NativeFunction(realm: self, name: name, length: length, fn)
    }

    /// Method defines a built-in method on an object: writable,
    /// configurable, not enumerable.
    public func Method(_ on: JSObject, _ name: string, _ length: int, _ fn: @escaping NativeFn) {
        let f = NativeFunction(realm: self, name: name, length: length, fn)
        on.DefineData(Key(name), .object(f), writable: true, enumerable: false, configurable: true)
    }

    /// SymbolMethod defines a method keyed by a well-known symbol.
    public func SymbolMethod(_ on: JSObject, _ sym: value.Symbol, _ length: int, writable: bool = true, configurable: bool = true, _ fn: @escaping NativeFn) {
        let f = NativeFunction(realm: self, symbolName: sym, prefix: "", length: length, fn)
        on.DefineData(.symbol(sym), .object(f), writable: writable, enumerable: false, configurable: configurable)
    }

    /// Getter defines a built-in accessor with only a getter.
    public func Getter(_ on: JSObject, _ key: PropertyKey, _ fn: @escaping NativeFn) {
        var name = ""
        switch key {
        case .string(let s): name = s.String
        case .symbol(let s): name = "[" + (s.Description?.String ?? "") + "]"
        case .index(let i): name = "\(i)"
        }
        let f = NativeFunction(realm: self, name: "get " + name, length: 0, fn)
        on.DefineAccessorDirect(key, getter: f, setter: nil, enumerable: false, configurable: true)
    }

    /// Accessor defines a built-in accessor pair.
    public func Accessor(_ on: JSObject, _ name: string, get: @escaping NativeFn, set: @escaping NativeFn) {
        let g = NativeFunction(realm: self, name: "get " + name, length: 0, get)
        let s = NativeFunction(realm: self, name: "set " + name, length: 1, set)
        on.DefineAccessorDirect(Key(name), getter: g, setter: s, enumerable: false, configurable: true)
    }

    /// Constructor makes a built-in constructor with its prototype object
    /// and defines it on the global object.
    public func Constructor(_ name: string, _ length: int, prototype: JSObject, global: bool = true, _ fn: @escaping NativeFn) -> NativeFunction {
        let f = NativeFunction(realm: self, name: name, length: length, constructor: true, fn)
        f.DefineData(keyPrototype, .object(prototype), writable: false, enumerable: false, configurable: false)
        prototype.DefineData(keyConstructor, .object(f), writable: true, enumerable: false, configurable: true)
        if global {
            Global.DefineData(Key(name), .object(f), writable: true, enumerable: false, configurable: true)
        }
        return f
    }

    /// Value defines a global value property.
    public func DefineGlobal(_ name: string, _ v: Value) {
        Global.DefineData(Key(name), v, writable: true, enumerable: false, configurable: true)
    }
}
