# js/codegen

Compiles a js/ast tree, after js/scope has analyzed it, into js/bytecode functions. Each function is compiled by a Builder.

```vertex
import "js/codegen"
```

## Types

- **`CompileError`** (enum): CompileError is a problem found while compiling (an early error the parser leaves to the compiler, or a construct not supported).
- **`ControlKind`** (enum)

## Functions

- `func CompileScript(_ prog: ast.Program, source: bytecode.SourceText) throws -> bytecode.FunctionTemplate`: CompileScript compiles an analyzed script into its top-level function.
- `func CompileEval(_ prog: ast.Program, source: bytecode.SourceText) throws -> bytecode.FunctionTemplate`: CompileEval compiles eval code. A sloppy eval's vars and functions are declared in the caller's var scope at runtime.
- `func Compile(_ prog: ast.Program, source: bytecode.SourceText) throws -> bytecode.FunctionTemplate`: Parse, analyze and compile a script in one step.

Part of the [`js`](https://github.com/vertex-language/js) repository.
