# js

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![js: ecmascript-engine](https://img.shields.io/badge/js-ecmascript--engine-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/js)
[![tests: 45/45 passing](https://img.shields.io/badge/tests-45%2F45%20passing-10b981?style=flat-square&labelColor=e4e4e7)](https://github.com/vertex-language/js)

A modern ECMAScript standard engine written in pure Vertex.

`js` provides a complete execution pipeline from source code to garbage-collected runtime: a fast lexer, recursive-descent parser, lexical scope analyzer, register-based bytecode compiler (Ignition architecture), virtual machine, tracing garbage collector integration (`gc`), and standard built-in intrinsics.

The engine has no C/C++ runtime dependencies, no Cgo, and compiles directly with `vsc`. It is completely decoupled from the browser and DOM, making it universally embeddable across desktop apps, CLI tools, server runtimes, game scripting, and the Vertex web engine (`web/script`).

---

## Architecture & Packages

The repository is organized into distinct, decoupled packages following a strict unidirectional pipeline:

```
Source Code
    │
    ▼
[js/scanner] ──(Tokens)──► [js/parser]
                                │
                                ▼ (AST)
                         [js/scope] ──► [js/printer] (Source round-trip)
                                │
                                ▼ (Scoped AST)
                         [js/codegen]
                                │
                                ▼ (BytecodeFunction)
                         [js/interp] ◄──► [js/object] ◄──► [js/builtin/*]
                                ▲                ▲
                                │                │
                           [js/value]        [js/str]
                                                 │
                                           [gc (Tracing Heap)]
```

### Package Overview

| Layer | Package | Description |
| :--- | :--- | :--- |
| **Front End** | `js/token` | Token kinds, keyword tables (reserved, contextual), precedences, source position tracking. |
| | `js/scanner` | UTF-8 lexer, numeric literals (decimal, hex, binary, octal, float), strings, templates, ASI. |
| | `js/ast` | Abstract Syntax Tree node definitions for expressions, statements, and declarations. |
| | `js/parser` | Recursive descent parser with operator precedence, cover grammars, and error recovery. |
| | `js/scope` | Lexical environment analyzer: variable hoisting, TDZ checks, duplicate declaration detection, closures. |
| | `js/printer` | AST to canonical JavaScript source formatter for round-trip validation. |
| **Bytecode** | `js/bytecode` | Register+accumulator instruction set, constant pool, position table, disassembler. |
| | `js/codegen` | AST to bytecode compiler, register allocation, compound assignment, calls, jumps. |
| **Runtime** | `js/value` | Unboxed tagged `Value` representation, ECMAScript type conversions (`ToBoolean`, `ToInt32`, `ToNumber`, `ToString`). |
| | `js/str` | UTF-16 `JSString` with Latin-1/2-byte storage, ropes, and atom interning. |
| | `js/object` | `Shape` transition trees (hidden classes), `JSObject` (`gc.Cell`), prototype inheritance, `Realm`. |
| | `js/ic` | Inline cache feedback vectors (uninitialized, monomorphic, polymorphic, megamorphic). |
| | `js/interp` | Register-based VM dispatch loop, stack frames, call resolution, exception handling, root provider. |
| | `js/module` | ES Module record definitions (`SourceTextModuleRecord`, imports, exports). |
| **Built-ins** | `js/builtin/global` | `globalThis`, `isFinite`, `isNaN`, `parseInt`, `parseFloat`, and diagnostic `gc()`. |
| | `js/builtin/fundamental` | `Object`, `Function`, `Boolean`, `Error`, `TypeError`. |
| | `js/builtin/numeric` | `Number`, `Math` (`abs`, `floor`, `ceil`, `round`, `min`, `max`, `sqrt`). |
| | `js/builtin/text` | `String` constructor and prototype methods (`charAt`, `charCodeAt`, `slice`, `indexOf`, `trim`, etc.). |
| | `js/builtin/indexed` | `Array` constructor, `isArray`, `push`, `pop`, `shift`, `unshift`, `join`, `slice`, `indexOf`. |
| | `js/builtin/keyed` | `Map`, `Set`, `WeakMap`, `WeakSet` (ephemeron pairs registered in `gc.Heap`). |
| | `js/builtin/memory` | `WeakRef` and `FinalizationRegistry` (resource cleanup notifications via `gc.Heap`). |
| | `js/builtin/structured` | `JSON.stringify` (with deterministic slot-order keys) and `JSON.parse`. |
| **RegExp** | `js/regexp/syntax` | ECMAScript RegExp flags (`g`, `i`, `m`, `s`, `u`, `y`) and pattern AST. |
| | `js/regexp` | Backtracking regex matcher engine with execution step budgeting. |
| **Embedding** | `js` | Root facade: `Agent`, `Realm`, `ObjectHandle`, `HandleScope`, `Exception`, `Eval`, `Call`, host hooks. |

---

## Quick Start

You can run any tool or example directly using the `vsc` CLI:

```bash
# 1. Run the end-to-end embedding example
vsc run example

# 2. Run the comprehensive regression test suite (45/45 tests)
vsc run check

# 3. Verify architectural layering rules across all 20 packages
vsc run check-deps

# 4. Disassemble sample JavaScript into bytecode instructions
vsc run dis

# 5. Start the interactive JavaScript REPL
vsc run repl
```

---

## Embedding & Usage Examples

### 1. Simple One-Line Evaluation

For quick calculations or scripting tasks, evaluate JavaScript code directly in a default agent realm:

```swift
package main

import "js"

func main() -> int32 {
    do {
        let result = try js.Eval("10 + 20 * 2")
        print("Result: \(result.ToInt32())") // 50
        return 0
    } catch {
        print("Error: \(error)")
        return 1
    }
}
```

### 2. Isolated Realm & Host Native Functions

Create an isolated `Realm` to register custom host functions and inject state into JavaScript's `globalThis`:

```swift
package main

import (
    "js"
    "js/value"
)

func main() -> int32 {
    let realm = js.Realm()

    // Expose a native host function: hostAdd(a, b)
    realm.DefineFunction("hostAdd") { args in
        let a = args.count > 0 ? args[0].ToNumber() : 0.0
        let b = args.count > 1 ? args[1].ToNumber() : 0.0
        return value.Value.Number(a + b)
    }

    // Expose a native logger
    realm.DefineFunction("hostLog") { args in
        var message = ""
        for i in 0..<args.count {
            if i > 0 { message += " " }
            message += args[i].ToString()
        }
        print("[Host] " + message)
        return value.Value.Undefined
    }

    // Inject configuration into globalThis
    let appConfig = realm.NewObject()
    appConfig.Set("env", value.Value.String("production"))
    appConfig.Set("retries", value.Value.Int(3))
    realm.Global.Set("Config", value.Value.Object(appConfig))

    // Run script
    let code = """
    hostLog("Running in:", Config.env);
    let total = hostAdd(100, 25);
    hostLog("Computed total:", total);
    JSON.stringify({ status: "ok", total: total });
    """

    do {
        let result = try realm.Eval(code)
        print("Outcome: " + result.ToString())
        return 0
    } catch {
        print("Execution failed: \(error)")
        return 1
    }
}
```

### 3. Garbage Collection & Memory Primitives

The engine is backed by the `gc` package's mark-sweep heap with exact tracing, write barriers, and ephemerons. Cyclic references are reclaimed cleanly, and modern ES2025 memory primitives (`WeakMap`, `WeakSet`, `WeakRef`, `FinalizationRegistry`) are natively supported:

```swift
package main

import "js"

func main() -> int32 {
    let realm = js.Realm()

    let script = """
    // 1. WeakMap with ephemeron semantics (keys do not retain values if key is dead)
    let wm = new WeakMap();
    let key = { id: 1 };
    wm.set(key, { secret: "payload" });
    let hasBefore = wm.has(key);

    // 2. WeakRef to observe reclamation
    let ref = new WeakRef(key);
    let alive = ref.deref() !== undefined;

    // 3. Trigger garbage collection cycle
    gc();

    JSON.stringify({ hasBefore: hasBefore, refAlive: alive });
    """

    let res = try! realm.Eval(script)
    print("GC demo result: " + res.ToString())
    return 0
}
```

### 4. Parsing, AST Inspection & Bytecode Disassembly

You can use the front end and bytecode packages independently for tooling, linting, or offline compilation:

```swift
package main

import (
    "js/parser"
    "js/codegen"
    "js/bytecode"
    "js/printer"
)

func main() -> int32 {
    let source = """
    function compute(x) {
        return x * 2 + 1;
    }
    """

    // 1. Parse source into an Abstract Syntax Tree
    let ast = try! parser.ParseScript(source, filename: "example.js")

    // 2. Format AST back to canonical source code
    let formatted = printer.Print(ast)
    print("Formatted:\n" + formatted)

    // 3. Compile AST to bytecode
    let bytecodeFunc = try! codegen.Compile(ast)

    // 4. Disassemble to Ignition-style instructions
    let dis = bytecode.Disassemble(bytecodeFunc)
    print("\nDisassembly:\n" + dis)

    return 0
}
```

---

## Architecture Layering Rules

The codebase strictly enforces unidirectional layering to ensure high maintainability and prevent circular dependencies. This is checked by `vsc run check-deps`:

1. **Front End Isolation:** `js/token`, `js/scanner`, `js/ast`, `js/parser`, `js/scope`, and `js/printer` never import any runtime packages.
2. **Built-in Isolation:** Built-in packages (`js/builtin/*`) never import `js/interp` or front-end packages.
3. **Mediated Execution:** `js/interp` never imports built-in packages directly; access to intrinsics is mediated through `Realm`.
4. **Universal Decoupling:** Nothing in `js` imports any DOM or browser package (`web`).

---

## Running Tools

### Disassembler (`cmd/dis`)
Inspect the generated bytecode for recursive functions, loops, and object manipulations:
```bash
vsc run dis
```

### Interactive REPL (`cmd/repl`)
Evaluate expressions interactively in a persistent Realm:
```bash
vsc run repl
```

### Verification & Tests (`cmd/check`)
Run the 45-point test harness verifying lexer tokens, AST nodes, scope analysis, shapes, strings, regex, VM evaluation, GC cycles, and memory primitives:
```bash
vsc run check
```

---

## License

[MIT](LICENSE)
