# js/parser

Builds a js/ast tree from source text (ECMA-262 §13–§16). It is a recursive-descent parser over js/scanner's tokens.

```vertex
import "js/parser"
```

## Types

- **`ParseError`** (enum): ParseError is a syntax error: a message, and where.
- **`Options`** (struct): Options adjusts what a parse accepts.

## Functions

- `func ParseScript(_ source: string, filename: string = "") throws -> ast.Program`: ParseScript parses a script.
- `func ParseModule(_ source: string, filename: string = "") throws -> ast.Program`: ParseModule parses a module: strict, with import and export.
- `func Parse(_ source: string, filename: string, options: Options) throws -> ast.Program`: Parse parses a program with options.
- `func ParseFunctionParts(params: string, body: string, isAsync: bool, isGenerator: bool) throws -> ast.FunctionNode`: ParseFunctionParts parses the parameter list and body text given to the Function constructor, as the spec does: each on its own.

Part of the [`js`](https://github.com/vertex-language/js) repository.
