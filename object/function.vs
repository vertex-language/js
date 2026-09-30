package object

import (
    "js/bytecode"
    "js/str"
    "js/value"
)

/// Context is a heap environment: the slots of the bindings closures
/// capture, chained to the context outside it.
public final class Context {
    public var Slots: [Value]
    public let Parent: Context?
    /// Info names the slots, for eval and with.
    public let Info: bytecode.ScopeInfo?
    /// WithObject makes this a with statement's object environment.
    public var WithObject: JSObject? = nil
    /// Extension holds the vars a sloppy direct eval declared here.
    public var Extension: JSObject? = nil

    public init(slots: int, parent: Context?, info: bytecode.ScopeInfo?) {
        self.Slots = [Value](repeating: .empty, count: slots)
        self.Parent = parent
        self.Info = info
    }

    public init(copying c: Context) {
        self.Slots = c.Slots
        self.Parent = c.Parent
        self.Info = c.Info
        self.WithObject = c.WithObject
        self.Extension = c.Extension
    }
}

/// FunctionEnv is the part of a function's environment that arrows and
/// eval share with it: this, new.target and the function itself (for
/// super and the home object).
public final class FunctionEnv {
    /// This is .empty in a derived constructor until super() returns.
    public var This: Value
    public var NewTarget: Value
    public var Function: JSFunction?

    public init(this: Value, newTarget: Value, function: JSFunction?) {
        self.This = this
        self.NewTarget = newTarget
        self.Function = function
    }
}

/// Engine is what runs ECMAScript function code: the interpreter,
/// installed on the realm. The object model calls through it so it needs
/// no knowledge of bytecode execution.
public protocol Engine: AnyObject {
    func CallFunction(_ f: JSFunction, _ this: Value, _ args: [Value]) throws -> Value
    func ConstructFunction(_ f: JSFunction, _ args: [Value], _ newTarget: JSObject) throws -> Value
    /// IndirectEval runs eval(x) not called directly: global scope.
    func IndirectEval(_ realm: Realm, _ source: str.JSString) throws -> Value
    /// CreateDynamicFunction is the Function, GeneratorFunction,
    /// AsyncFunction and AsyncGeneratorFunction constructors (§20.2.1.1.1).
    func CreateDynamicFunction(_ realm: Realm, _ args: [Value], _ newTarget: JSObject?, isAsync: bool, isGenerator: bool) throws -> JSObject
    /// StackTrace describes the running frames, for Error.prototype.stack.
    func StackTrace() -> string
}

public typealias NativeFn = (Value, [Value], JSObject?) throws -> Value

/// NativeFunction is a built-in function object (§10.3).
public final class NativeFunction: JSObject {
    let fn: NativeFn
    let constructible: bool
    public let Realm: Realm

    public init(realm: Realm, name: string, length: int, constructor: bool = false, proto: JSObject? = nil, _ fn: @escaping NativeFn) {
        self.fn = fn
        self.constructible = constructor
        self.Realm = realm
        super.init(proto: proto ?? realm.FunctionPrototype)
        self.Kind = .function
        self.DefineData(keyLength, .number(float64(length)), writable: false, enumerable: false, configurable: true)
        self.DefineData(keyName, .string(str.JSString.From(name)), writable: false, enumerable: false, configurable: true)
    }

    public init(realm: Realm, symbolName: value.Symbol, prefix: string, length: int, _ fn: @escaping NativeFn) {
        self.fn = fn
        self.constructible = false
        self.Realm = realm
        super.init(proto: realm.FunctionPrototype)
        self.Kind = .function
        self.DefineData(keyLength, .number(float64(length)), writable: false, enumerable: false, configurable: true)
        var n = prefix
        if let d = symbolName.Description { n += "[" + d.String + "]" }
        self.DefineData(keyName, .string(str.JSString.From(n)), writable: false, enumerable: false, configurable: true)
    }

    public override var IsCallable: bool { return true }
    public override var IsConstructor: bool { return constructible }

    public override func Call(_ this: Value, _ args: [Value]) throws -> Value {
        let saved = currentRealmStorage
        currentRealmStorage = Realm
        defer { currentRealmStorage = saved }
        return try fn(this, args, nil)
    }

    public override func Construct(_ args: [Value], _ newTarget: JSObject) throws -> Value {
        let saved = currentRealmStorage
        currentRealmStorage = Realm
        defer { currentRealmStorage = saved }
        return try fn(.undefined, args, newTarget)
    }
}

/// ClassField is one instance field a class constructor defines.
public final class ClassField {
    public let Key: value.PropertyKey
    public let Initializer: JSObject?
    public init(key: value.PropertyKey, initializer: JSObject?) {
        self.Key = key
        self.Initializer = initializer
    }
}

/// PrivateMethod is an instance private method or accessor.
public final class PrivateMethod {
    public let Name: value.Symbol
    public var Method: JSObject?
    public var Getter: JSObject?
    public var Setter: JSObject?
    public init(name: value.Symbol) {
        self.Name = name
    }
}

/// JSFunction is an ECMAScript function object (§10.2): compiled code
/// closed over a context.
public final class JSFunction: JSObject {
    public let Template: bytecode.FunctionTemplate
    public let Env: Context?
    /// FuncEnv is the enclosing function's environment, for an arrow.
    public var FuncEnv: FunctionEnv?
    public var HomeObject: JSObject?
    /// Fields and PrivateMethods are a class constructor's instance
    /// elements, in order.
    public var Fields: [ClassField] = []
    public var PrivateMethods: [PrivateMethod] = []
    public let Realm: Realm
    /// ScriptOrModule is the module a function belongs to, for import().
    public var Module: JSObject? = nil

    public init(template: bytecode.FunctionTemplate, env: Context?, realm: Realm, proto: JSObject) {
        self.Template = template
        self.Env = env
        self.Realm = realm
        super.init(proto: proto)
        self.Kind = .function
    }

    public override var IsCallable: bool { return true }
    public override var IsConstructor: bool { return Template.IsConstructor }

    public var IsClassConstructor: bool { return Template.IsClassConstructor }

    public override func Call(_ this: Value, _ args: [Value]) throws -> Value {
        if Template.IsClassConstructor {
            let n = Template.Name.String
            throw ThrowTypeError("Class constructor \(n) cannot be invoked without 'new'")
        }
        return try Realm.Engine!.CallFunction(self, this, args)
    }

    public override func Construct(_ args: [Value], _ newTarget: JSObject) throws -> Value {
        return try Realm.Engine!.ConstructFunction(self, args, newTarget)
    }
}

/// BoundFunction is a bound function exotic object (§10.4.1).
public final class BoundFunction: JSObject {
    public let Target: JSObject
    public let BoundThis: Value
    public let BoundArgs: [Value]

    public init(target: JSObject, boundThis: Value, boundArgs: [Value], proto: JSObject?) {
        self.Target = target
        self.BoundThis = boundThis
        self.BoundArgs = boundArgs
        super.init(proto: proto)
        self.Kind = .function
    }

    public override var IsCallable: bool { return true }
    public override var IsConstructor: bool { return Target.IsConstructor }

    public override func Call(_ this: Value, _ args: [Value]) throws -> Value {
        var all = BoundArgs
        all.append(contentsOf: args)
        return try Target.Call(BoundThis, all)
    }

    public override func Construct(_ args: [Value], _ newTarget: JSObject) throws -> Value {
        var all = BoundArgs
        all.append(contentsOf: args)
        var nt = newTarget
        if nt === self { nt = Target }
        return try Target.Construct(all, nt)
    }
}

/// SetFunctionName (§10.2.9) defines a function's name property.
public func SetFunctionName(_ f: JSObject, _ key: value.PropertyKey, prefix: string = "") {
    var name: str.JSString
    switch key {
    case .symbol(let s):
        if s.IsPrivate {
            name = s.Description ?? str.JSString.Empty
        } else if let d = s.Description {
            name = str.JSString.From("[" + d.String + "]")
        } else {
            name = str.JSString.Empty
        }
    case .string(let s):
        name = s
    case .index(let i):
        name = str.JSString.From("\(i)")
    }
    if !prefix.isEmpty {
        name = str.JSString.From(prefix + " ").Concat(name)
    }
    _ = try? f.DefineOwnProperty(keyName, PropertyDescriptor.Data(.string(name), writable: false, enumerable: false, configurable: true))
}

/// MakeConstructor gives a function its prototype object (§10.2.5).
public func MakeConstructor(_ f: JSObject, realm: Realm, proto: JSObject? = nil, writable: bool = true) {
    let p = proto ?? JSObject(proto: realm.ObjectPrototype)
    if proto == nil {
        p.DefineData(keyConstructor, .object(f), writable: true, enumerable: false, configurable: true)
    }
    f.DefineData(keyPrototype, .object(p), writable: writable, enumerable: false, configurable: false)
}
