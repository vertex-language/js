# js/builtin/fundamental

Installs the fundamental objects (ECMA-262 §20): Object, Function, Boolean, Symbol, and Error with its native errors.

```vertex
import "js/builtin/fundamental"
```

## Functions

- `func Install(_ r: object.Realm)`: Install defines the fundamental objects in a realm.
- `func groupBy(_ items: Value, _ cb: Value, propertyKeys: bool) throws -> [(Value, [Value])]`: groupBy is GroupBy (§7.3.35): the groups in first-seen order.
- `func ObjectToString(_ v: Value) throws -> str.JSString`: ObjectToString is Object.prototype.toString (§20.1.3.6).
- `func FunctionToString(_ v: Value) throws -> string`: FunctionToString is Function.prototype.toString (§20.2.3.5).

Part of the [`js`](https://github.com/vertex-language/js) repository.
