# js/bytecode

The instruction set the compiler emits and the interpreter runs: a register machine with an accumulator, after V8's Ignition.

```vertex
import "js/bytecode"
```

## Types

- **`Opcode`** (enum)
- **`Instruction`** (struct): Instruction is one operation and its operands.
- **`TemplateInfo`** (class): TemplateInfo is a tagged template call site's strings.
- **`GlobalDecls`** (class): GlobalDecls is what a script declares at its top level, for GlobalDeclarationInstantiation.
- **`Constant`** (enum): Constant is one entry of a function's constant pool.
- **`Handler`** (struct): Handler is one entry of the exception table: a throw from an instruction in [Start, End) goes to Target with the exception in the accumulator.
- **`ScopeInfo`** (class): ScopeInfo names the slots of a context, so that eval and with can find bindings by name at runtime.
- **`FunctionKind`** (enum)
- **`FunctionTemplate`** (class): FunctionTemplate is a compiled function: code plus everything a closure of it needs.
- **`SourceText`** (class): SourceText is a script's text, shared by its functions.

## Functions

- `func Disassemble(_ fn: FunctionTemplate) -> string`: Disassemble prints a function and the functions nested in it.

Part of the [`js`](https://github.com/vertex-language/js) repository.
