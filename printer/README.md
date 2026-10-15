# js/printer

A syntax tree back to source.

```vertex
import "js/printer"
```

## Functions

- `func Print(_ program: ast.Program) -> string`: Print renders an AST Program as JavaScript source text.
- `func PrintStmt(_ stmt: ast.Stmt) -> string`: PrintStmt renders an individual statement as source text.
- `func PrintExpr(_ expr: ast.Expr) -> string`: PrintExpr renders an expression as source text.

Part of the [`js`](https://github.com/vertex-language/js) repository.
