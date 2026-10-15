# js/str

ECMAScript's String type: a sequence of UTF-16 code units (ECMA-262 §6.1.4). Concatenation builds a rope, so a loop that appends to a string costs linear time; the rope is flattened the first time its units are read.

```vertex
import "js/str"
```

## Types

- **`JSString`** (class): JSString is an immutable string of UTF-16 code units.
- **`AtomTable`** (class): Intern returns the one JSString for an ASCII or UTF-8 name, so names the compiler and the built-ins share are the same object and compare by identity first.
- **`Builder`** (struct): Builder accumulates code units.

## Functions

- `func Name(_ s: string) -> JSString`: Name interns a UTF-8 name.

Part of the [`js`](https://github.com/vertex-language/js) repository.
