# js/scanner

Turns ECMAScript source text into tokens (ECMA-262 §12). The scanner reads on demand.

```vertex
import "js/scanner"
```

## Types

- **`ScanError`** (enum): ScanError is a lexical error at a byte offset.
- **`State`** (struct): State is a scanner position that Save returns and Restore goes back to, for the parser's lookahead.
- **`Scanner`** (class): Scanner reads tokens from UTF-8 source.

## Functions

- `func parseDecimal(_ text: string) -> float64`: parseDecimal converts a decimal literal's digits (no separators) to the nearest double.

Part of the [`js`](https://github.com/vertex-language/js) repository.
