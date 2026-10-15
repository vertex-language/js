# js/regexp/syntax

Parses ECMAScript regular expressions (ECMA-262 §22.2.1) into a tree the js/regexp compiler turns into a program.

```vertex
import "js/regexp/syntax"
```

## Types

- **`Flags`** (struct): Flags are a regular expression's flags.
- **`CharSet`** (class): CharSet is a class: code points as sorted, merged ranges, flat [first, last, first, last, ...], and, under the v flag, strings of other than one code point (\q{abc}, \p{RGI_Emoji}).
- **`NodeKind`** (enum): NodeKind is what a node matches.
- **`Node`** (class): Node is one part of a pattern, with the modifiers in force where it appears (i, m and s may change inside (?ims-ims:...)).
- **`Pattern`** (class): Pattern is a parsed regular expression.
- **`SyntaxError`** (struct): SyntaxError is an invalid pattern.

## Functions

- `func ParseFlags(_ f: [uint16]) -> Flags?`: ParseFlags reads flag characters; nil when one is unknown, repeated, or u and v are both given.
- `func Parse(_ source: [uint16], _ flags: Flags) throws -> Pattern`: Parse parses a pattern's source (UTF-16) under flags.

Part of the [`js`](https://github.com/vertex-language/js) repository.
