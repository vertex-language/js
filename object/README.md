# js/object

The runtime's object model: the Value type, objects and their internal methods (ECMA-262 §10), the realm and its intrinsics, and the abstract operations of §7 that everything above (the interpreter, the built-ins) is written in terms of.

```vertex
import "js/object"
```

## Types

- **`ArrayObject`** (class): ArrayObject is an Array exotic object (§10.4.2).
- **`ArgumentsObject`** (class): ArgumentsObject is an arguments exotic object (§10.4.4). A mapped one aliases its elements to the function's parameter slots in a context.
- **`StringObject`** (class): StringObject is a String exotic object (§10.4.3): its code units are read-only indexed properties.
- **`Context`** (class): Context is a heap environment: the slots of the bindings closures capture, chained to the context outside it.
- **`FunctionEnv`** (class): FunctionEnv is the part of a function's environment that arrows and eval share with it: this, new.target and the function itself (for super and the home object).
- **`Engine`** (protocol): Engine is what runs ECMAScript function code: the interpreter, installed on the realm.
- **`NativeFn`** (typealias)
- **`NativeFunction`** (class): NativeFunction is a built-in function object (§10.3).
- **`ClassField`** (class): ClassField is one instance field a class constructor defines.
- **`PrivateMethod`** (class): PrivateMethod is an instance private method or accessor.
- and 24 more

## Functions

- `func SetFunctionName(_ f: JSObject, _ key: value.PropertyKey, prefix: string = "")`: SetFunctionName (§10.2.9) defines a function's name property.
- `func MakeConstructor(_ f: JSObject, realm: Realm, proto: JSObject? = nil, writable: bool = true)`: MakeConstructor gives a function its prototype object (§10.2.5).
- `func GetIteratorFromMethod(_ obj: Value, _ method: Value) throws -> IteratorRecord`: GetIteratorFromMethod (§7.4.2).
- `func GetIterator(_ obj: Value) throws -> IteratorRecord`: GetIterator (§7.4.3) for sync iteration.
- `func GetAsyncIterator(_ obj: Value) throws -> IteratorRecord`: GetAsyncIterator is GetIterator(obj, async): a sync iterator is wrapped in an async-from-sync iterator.
- `func DescribeIterable(_ v: Value) -> string`: DescribeIterable names a value in "x is not iterable" as V8 does.
- `func IteratorNext(_ r: IteratorRecord, _ v: Value? = nil) throws -> JSObject`: IteratorNext (§7.4.4).
- `func IteratorComplete(_ o: JSObject) throws -> bool`: IteratorComplete (§7.4.5).
- `func IteratorValue(_ o: JSObject) throws -> Value`: IteratorValue (§7.4.6).
- `func IteratorStepValue(_ r: IteratorRecord) throws -> Value?`: IteratorStepValue (§7.4.8): the next value, or nil when done.
- and 91 more

Part of the [`js`](https://github.com/vertex-language/js) repository.
