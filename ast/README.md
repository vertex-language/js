# js/ast

The syntax tree the parser builds (ECMA-262 §13–§16).

```vertex
import "js/ast"
```

## Types

- **`BindingKind`** (enum): BindingKind is how a name was declared.
- **`Binding`** (class): Binding is one declared name in one scope.
- **`ScopeKind`** (enum): ScopeKind is what introduced a scope.
- **`Scope`** (class): Scope is a static scope. The compiler lays out its bindings.
- **`Program`** (class)
- **`Expr`** (enum)
- **`Pos`** (class): Pos is a bare source position, for the payloads that need nothing else.
- **`NumberLit`** (class)
- **`BigIntLit`** (class)
- **`StringLit`** (class)
- and 64 more

## Functions

- `func ExprPos(_ e: Expr) -> int`: ExprPos is an expression's source offset.
- `func StripParens(_ e: Expr) -> Expr`: StripParens removes the parentheses around an expression.
- `func IsAnonymousFunctionDefinition(_ e: Expr) -> bool`: IsAnonymousFunctionDefinition is the spec's test for giving an anonymous function or class the name of what it is assigned to.
- `func PatternNames(_ p: Pattern, _ out: inout [string])`: PatternNames lists the names a binding pattern declares, in order.

Part of the [`js`](https://github.com/vertex-language/js) repository.
