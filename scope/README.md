# js/scope

The static semantics of names (ECMA-262 §8.1, §9.1): it builds the tree of scopes, declares every binding, resolves every identifier, and lays the bindings out in registers and context slots.

```vertex
import "js/scope"
```

## Types

- **`ScopeError`** (enum): ScopeError is an early error the analysis finds (a redeclaration).
- **`Mode`** (enum): Mode is what kind of code is analyzed.

## Functions

- `func Analyze(_ prog: ast.Program, mode: Mode = .script) throws -> ast.Scope`: Analyze analyzes a program and returns its top scope.

Part of the [`js`](https://github.com/vertex-language/js) repository.
