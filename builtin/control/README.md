# js/builtin/control

Installs the control abstraction objects (ECMA-262 §27): Iterator and its helpers, %AsyncIteratorPrototype%, Promise, and the GeneratorFunction, AsyncGeneratorFunction and AsyncFunction constructors.

```vertex
import "js/builtin/control"
```

## Types

- **`IteratorHelper`** (class): IteratorHelper is an Iterator Helper object (§27.1.2.1): its steps are a Vertex closure over the underlying iterator.
- **`WrappedIterator`** (class): WrappedIterator is Iterator.from's wrapper (§27.1.3.2.1.1).

## Functions

- `func Install(_ r: object.Realm)`: Install defines the control abstraction objects.

Part of the [`js`](https://github.com/vertex-language/js) repository.
