package object

import (
    "gc"
    "js/value"
    "js/str"
    "js/bytecode"
)

/// PropertyDescriptor models ECMA-262 Property Descriptor records.
public struct PropertyDescriptor: Equatable {
    public var Value: value.Value
    public var Writable: bool
    public var Enumerable: bool
    public var Configurable: bool
    public var Get: JSObject?
    public var Set: JSObject?

    public init(value: value.Value = value.Value.Undefined, writable: bool = true, enumerable: bool = true, configurable: bool = true, get: JSObject? = nil, set: JSObject? = nil) {
        self.Value = value
        self.Writable = writable
        self.Enumerable = enumerable
        self.Configurable = configurable
        self.Get = get
        self.Set = set
    }
}

/// ShapeProperty records the slot offset and attributes of a property in a Shape.
public struct ShapeProperty: Equatable {
    public var Key: string
    public var Slot: int
    public var Writable: bool
    public var Enumerable: bool
    public var Configurable: bool

    public init(key: string, slot: int, writable: bool = true, enumerable: bool = true, configurable: bool = true) {
        self.Key = key
        self.Slot = slot
        self.Writable = writable
        self.Enumerable = enumerable
        self.Configurable = configurable
    }
}

/// Shape represents an object layout transition node.
public final class Shape {
    public weak var Parent: Shape?
    public var Properties: [string: ShapeProperty] = [:]
    public var Transitions: [string: Shape] = [:]
    public var PropertyCount: int

    public init(parent: Shape? = nil, propertyCount: int = 0) {
        self.Parent = parent
        self.PropertyCount = propertyCount
    }

    public static func Root() -> Shape {
        return Shape()
    }

    public func Lookup(_ key: string) -> ShapeProperty? {
        return Properties[key]
    }

    public func AddProperty(key: string, writable: bool = true, enumerable: bool = true, configurable: bool = true) -> Shape {
        if let existing = Transitions[key] {
            return existing
        }
        let next = Shape(parent: self, propertyCount: PropertyCount + 1)
        next.Properties = self.Properties
        let prop = ShapeProperty(key: key, slot: PropertyCount, writable: writable, enumerable: enumerable, configurable: configurable)
        next.Properties[key] = prop
        Transitions[key] = next
        return next
    }
}

/// NativeFunctionSignature is the host callback signature for native built-ins.
public typealias NativeCallback = (Realm, value.Value, [value.Value]) throws -> value.Value

/// CallableObject holds either native callback or compiled bytecode function.
public enum CallableObject {
    case native(NativeCallback)
    case bytecode(bytecode.BytecodeFunction)
}

/// JSObject represents an ECMAScript object in the runtime managed by the garbage collector.
public final class JSObject: gc.Cell {
    public var CurrentShape: Shape
    public var Slots: [value.Value] = []
    public var Elements: [value.Value] = []
    public var Prototype: JSObject?
    public var Callable: CallableObject?
    public var IsConstructor: bool = false
    public var InternalTag: string = "Object"
    public var NativeData: AnyObject? = nil
    public var ElementHook: ((JSObject, int, value.Value?) -> value.Value?)? = nil

    public init(shape: Shape? = nil, prototype: JSObject? = nil) {
        self.CurrentShape = shape ?? Shape.Root()
        self.Prototype = prototype
        super.init(typeTag: 10, size: 64)
        self.TraceCallback = { cell, tracer in
            if let obj = cell as? JSObject {
                obj.traceObject(with: tracer)
            }
        }
    }

    func traceObject(with tracer: gc.Tracer) {
        if let p = Prototype {
            tracer.Visit(p)
        }
        for s in Slots {
            if s.Type == .object, let c = s.ObjVal as? gc.Cell {
                tracer.Visit(c)
            }
        }
        for e in Elements {
            if e.Type == .object, let c = e.ObjVal as? gc.Cell {
                tracer.Visit(c)
            }
        }
        if let data = NativeData as? gc.Cell {
            tracer.Visit(data)
        }
    }

    public override func Trace(with tracer: gc.Tracer) {
        super.Trace(with: tracer)
        traceObject(with: tracer)
    }

    // [[Get]]
    public func Get(_ key: string) -> value.Value {
        if let prop = CurrentShape.Lookup(key) {
            if prop.Slot < Slots.count {
                return Slots[prop.Slot]
            }
        }
        // Walk prototype chain
        var cur = Prototype
        while let p = cur {
            if let prop = p.CurrentShape.Lookup(key) {
                if prop.Slot < p.Slots.count {
                    return p.Slots[prop.Slot]
                }
            }
            cur = p.Prototype
        }
        return value.Value.Undefined
    }

    // [[Set]]
    public func Set(_ key: string, _ val: value.Value) {
        if let prop = CurrentShape.Lookup(key) {
            if prop.Slot < Slots.count {
                Slots[prop.Slot] = val
                triggerWriteBarrier(val)
                return
            }
        }
        // Transition shape
        CurrentShape = CurrentShape.AddProperty(key: key)
        while Slots.count < CurrentShape.PropertyCount {
            Slots.append(value.Value.Undefined)
        }
        if let prop = CurrentShape.Lookup(key) {
            Slots[prop.Slot] = val
            triggerWriteBarrier(val)
        }
    }

    func triggerWriteBarrier(_ val: value.Value) {
        if val.Type == .object, let target = val.ObjVal as? gc.Cell, let heap = HeapRef as? gc.Heap {
            let tracer = gc.Tracer()
            heap.Barrier.OnWrite(source: self, target: target, tracer: tracer)
        }
    }

    // [[HasProperty]]
    public func Has(_ key: string) -> bool {
        if CurrentShape.Lookup(key) != nil {
            return true
        }
        var cur = Prototype
        while let p = cur {
            if p.CurrentShape.Lookup(key) != nil { return true }
            cur = p.Prototype
        }
        return false
    }

    // Indexed elements
    public func GetElement(_ index: int) -> value.Value {
        if let hook = ElementHook {
            if let val = hook(self, index, nil) {
                return val
            }
        }
        if index >= 0 && index < Elements.count {
            return Elements[index]
        }
        return Get("\(index)")
    }

    public func SetElement(_ index: int, _ val: value.Value) {
        if let hook = ElementHook {
            if hook(self, index, val) != nil {
                return
            }
        }
        if index >= 0 {
            while Elements.count <= index {
                Elements.append(value.Value.Undefined)
            }
            Elements[index] = val
            triggerWriteBarrier(val)
            // Update length property if array
            if InternalTag == "Array" {
                let len = Elements.count
                Set("length", value.Value.Int(int32(len)))
            }
            return
        }
        Set("\(index)", val)
    }

    /// Keys returns all own enumerable property keys sorted by insertion (slot) order.
    public var Keys: [string] {
        var props: [ShapeProperty] = []
        for (_, prop) in CurrentShape.Properties where prop.Enumerable {
            props.append(prop)
        }
        props.sort { $0.Slot < $1.Slot }
        var k: [string] = []
        for p in props {
            k.append(p.Key)
        }
        return k
    }
}

/// Realm record holding intrinsics, heap manager, and the global environment.
public final class Realm {
    public let Heap: gc.Heap
    public let GlobalObject: JSObject
    public let ObjectPrototype: JSObject
    public let FunctionPrototype: JSObject
    public let ArrayPrototype: JSObject
    public let ErrorPrototype: JSObject

    public init() {
        let heap = gc.NewHeap()
        self.Heap = heap

        let objProto = heap.Allocate(JSObject(prototype: nil), size: 64, typeTag: 10)
        let fnProto = heap.Allocate(JSObject(prototype: objProto), size: 64, typeTag: 10)
        let arrProto = heap.Allocate(JSObject(prototype: objProto), size: 64, typeTag: 10)
        let errProto = heap.Allocate(JSObject(prototype: objProto), size: 64, typeTag: 10)
        let globObj = heap.Allocate(JSObject(prototype: objProto), size: 64, typeTag: 10)

        self.ObjectPrototype = objProto
        self.FunctionPrototype = fnProto
        self.ArrayPrototype = arrProto
        self.ErrorPrototype = errProto
        self.GlobalObject = globObj

        ObjectPrototype.InternalTag = "Object"
        FunctionPrototype.InternalTag = "Function"
        ArrayPrototype.InternalTag = "Array"
        ErrorPrototype.InternalTag = "Error"
        GlobalObject.InternalTag = "Global"

        GlobalObject.Set("globalThis", value.Value.Object(GlobalObject))

        // Root permanent realm intrinsics
        heap.Roots.AddRoot(GlobalObject)
        heap.Roots.AddRoot(ObjectPrototype)
        heap.Roots.AddRoot(FunctionPrototype)
        heap.Roots.AddRoot(ArrayPrototype)
        heap.Roots.AddRoot(ErrorPrototype)
    }

    public func NewObject(prototype: JSObject? = nil) -> JSObject {
        let proto = prototype ?? ObjectPrototype
        let obj = JSObject(prototype: proto)
        return Heap.Allocate(obj, size: 64, typeTag: 10)
    }

    public func NewArray(elements: [value.Value] = []) -> JSObject {
        let arr = JSObject(prototype: ArrayPrototype)
        arr.InternalTag = "Array"
        arr.Elements = elements
        arr.Set("length", value.Value.Int(int32(elements.count)))
        return Heap.Allocate(arr, size: 64 + elements.count * 16, typeTag: 10)
    }

    public func NewFunction(name: string, _ callback: @escaping NativeCallback) -> JSObject {
        let fn = JSObject(prototype: FunctionPrototype)
        fn.Callable = .native(callback)
        fn.Set("name", value.Value.String(name))
        return Heap.Allocate(fn, size: 64, typeTag: 10)
    }

    public func NewBytecodeFunction(_ code: bytecode.BytecodeFunction) -> JSObject {
        let fn = JSObject(prototype: FunctionPrototype)
        fn.Callable = .bytecode(code)
        fn.IsConstructor = true
        fn.Set("name", value.Value.String(code.Name))
        fn.Set("length", value.Value.Int(int32(code.ParameterCount)))
        let proto = NewObject()
        let fnObj = Heap.Allocate(fn, size: 64, typeTag: 10)
        proto.Set("constructor", value.Value.Object(fnObj))
        fnObj.Set("prototype", value.Value.Object(proto))
        return fnObj
    }

    // Microtask queue & VM call hook
    public var EnqueueJobHook: ((@escaping () -> Void) -> Void)? = nil
    var microtasks: [() -> Void] = []
    public var CallHook: ((Realm, JSObject, value.Value, [value.Value]) throws -> value.Value)? = nil

    public func EnqueueJob(_ job: @escaping () -> Void) {
        if let hook = EnqueueJobHook {
            hook(job)
        } else {
            microtasks.append(job)
        }
    }

    public func RunJobs() {
        var count = 0
        while !microtasks.isEmpty && count < 10000 {
            count += 1
            let job = microtasks.removeFirst()
            job()
        }
    }

    public func Call(_ obj: JSObject, thisVal: value.Value = value.Value.Undefined, args: [value.Value] = []) throws -> value.Value {
        guard let callable = obj.Callable else {
            return value.Value.Undefined
        }
        switch callable {
        case .native(let cb):
            return try cb(self, thisVal, args)
        case .bytecode:
            if let hook = CallHook {
                return try hook(self, obj, thisVal, args)
            }
            return value.Value.Undefined
        }
    }
}

