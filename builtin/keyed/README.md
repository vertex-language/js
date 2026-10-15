# js/builtin/keyed

Installs the keyed collections (ECMA-262 §24): Map, Set, WeakMap and WeakSet, with their iterators.

```vertex
import "js/builtin/keyed"
```

## Types

- **`Key`** (struct): Key is a value as a hash key under SameValueZero: -0 is +0, every NaN is one NaN, objects and symbols are themselves.
- **`Table`** (class): Table is a Map's or Set's entries: insertion ordered, with deleted entries left as .empty so that iterators keep their place.
- **`Collection`** (class): Collection is a Map or Set instance.
- **`WeakCollection`** (class): WeakCollection is a WeakMap or WeakSet.
- **`IterationKind`** (enum)
- **`CollectionIterator`** (class)

## Functions

- `func CanBeHeldWeakly(_ v: Value) -> bool`: CanBeHeldWeakly (§9.13).
- `func Install(_ r: object.Realm)`

Part of the [`js`](https://github.com/vertex-language/js) repository.
