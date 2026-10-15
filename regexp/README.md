# js/regexp

Compiles a js/regexp/syntax tree to a program for a backtracking matcher over UTF-16 code units, with the semantics of ECMA-262 §22.2.2: captures reset on each iteration of a quantifier, an iteration past the minimum may not match empty, lookbehind matches right to left.

```vertex
import "js/regexp"
```

## Types

- **`Program`** (class): Program is a compiled regular expression.

Part of the [`js`](https://github.com/vertex-language/js) repository.
