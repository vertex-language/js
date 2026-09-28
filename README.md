# js

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![js: ecmascript-engine](https://img.shields.io/badge/js-ecmascript--engine-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/js)
[![tests: 59/59 passing](https://img.shields.io/badge/tests-59%2F59%20passing-10b981?style=flat-square&labelColor=e4e4e7)](https://github.com/vertex-language/js)

A modern ECMAScript standard engine written in pure Vertex.

`js` provides a complete execution pipeline from source code to garbage-collected runtime: a fast lexer, recursive-descent parser, lexical scope analyzer, register-based bytecode compiler (Ignition architecture), virtual machine, tracing garbage collector integration (`gc`), and standard built-in intrinsics.

The engine has no C/C++ runtime dependencies, no Cgo, and compiles directly with `vsc`. It is completely decoupled from the browser and DOM, making it universally embeddable across desktop apps, CLI tools, server runtimes, game scripting, and the Vertex web engine (`web/script`).

---

## Target Specification & Coverage

- **Target Standard:** **ECMAScript 2026 (ECMA-262, 17th Edition)**
- **Conformance Target:** Official ECMAScript Conformance Test Suite (**test262**)
- **Architecture Philosophy:** Universal embedding, pure Vertex (`.vs`), fast register-accumulator bytecode (Ignition design), unboxed tagged values, shape-based property transitions, and precise traced garbage collection (`gc`).

### ECMA-262 Specification Status Matrix

| ECMA-262 Chapter | Specification Scope | Status | Implementation Details |
| :--- | :--- | :---: | :--- |
| **§6–§9: Types & Conversions** | Values, primitives, records, `ToBoolean`, `ToInt32`, `ToNumber`, `ToString` | **Complete** | Tagged unboxed `Value` representation, NaN/overflow wrapping, abstract (`==`) and strict (`===`) equality. |
| **§10–§11: Source & Lexer** | UTF-8 scanning, keywords, literals, template strings, ASI | **Complete** | Full lexer in `js/scanner`, decimal/hex/binary/octal/float literals, ASI tracking, comment preservation. |
| **§12–§14: Statements & Syntax** | AST, expressions, precedence, declarations (`var`, `let`, `const`), loops, control flow | **Complete** | Recursive descent parser in `js/parser`, lexical environments & TDZ in `js/scope`, AST formatting in `js/printer`. |
| **§15: Functions & Classes** | Functions, closures, recursion, constructors, `class`, `extends`, `super` | **Complete** | Full function expressions, declarations, closures, constructor calls (`new Ctor`). ES6 `class` declarations and expressions, `extends` inheritance, `super()` constructor delegation, `super.method()` prototype invocation, and `static` methods. |
| **§16: Modules** | Static module records, imports, exports | **Built** | `SourceTextModuleRecord`, `ImportEntry`, `ExportEntry` structures in `js/module`. |
| **§19: Global Object** | `globalThis`, `isFinite`, `isNaN`, `parseInt`, `parseFloat`, `gc()`, timers | **Complete** | Standard global functions, `globalThis` linkage, `setTimeout`/`clearTimeout`/`setInterval`/`clearInterval` task timers, diagnostic GC trigger. |
| **§20: Fundamental Objects** | `Object`, `Function`, `Boolean`, `Error`, `TypeError`, `RangeError`, `SyntaxError` | **Complete** | Prototypes, shape transition trees (`js/object`), `Object.keys`, `Object.getPrototypeOf`, `Function.prototype.call`. |
| **§21: Numbers & Math** | `Number`, `Math` (`abs`, `floor`, `ceil`, `round`, `min`, `max`, `sqrt`) | **Complete** | Full IEEE-754 double operations in `js/builtin/numeric`. (`Date` pending `time` package integration). |
| **§22: Text Processing** | `String` methods, `RegExp` pattern AST, regex backtracking engine | **Complete** | UTF-16 Latin-1/2-byte `JSString` ropes and atoms, regex matcher supporting flags `g`, `i`, `m`, `s`, `u`, `y`. |
| **§23: Indexed Collections** | `Array` constructor, `isArray`, `push`, `pop`, `shift`, `unshift`, `join`, `slice`, `indexOf` | **Complete** | Contiguous element storage with dynamic resizing in `js/builtin/indexed`. |
| **§24: Keyed Collections** | `Map`, `Set`, `WeakMap`, `WeakSet` | **Complete** | Full hash-based `Map` and `Set`. `WeakMap` and `WeakSet` backed by GC ephemeron tables (`gc.Heap.Ephemerons`). |
| **§25: Structured Data** | `JSON.stringify`, `JSON.parse`, `ArrayBuffer`, `DataView`, `TypedArray` family | **Complete** | `JSON`, `ArrayBuffer`, `DataView`, and complete `TypedArray` family (`Int8Array`, `Uint8Array`, `Uint8ClampedArray`, `Int16Array`, `Uint16Array`, `Int32Array`, `Uint32Array`, `Float32Array`, `Float64Array`). |
| **§26: Managing Memory** | `WeakRef`, `FinalizationRegistry`, Traced Heap, Write Barriers, Ephemerons | **Complete** | `JSObject` inherits from `gc.Cell`. Exact tracing, write barriers, root providers, weak references, cleanup callbacks. |
| **§27: Control Abstraction** | Microtask queue, `Promise` (`then`, `catch`, `finally`, combinators), `queueMicrotask` | **Complete** | `Promise` constructor, thenable unwrapping, microtask reactions, combinators (`all`, `race`, `allSettled`, `any`), `queueMicrotask`. |
| **§28: Reflection** | `Reflect` namespace and `Proxy` with 13 internal traps | **Planned** | Dynamic interception traps scheduled for Phase 3. |
| **ECMA-402: Internationalization**| `Intl.DateTimeFormat`, `Intl.NumberFormat`, `Intl.Collator` | **Planned** | Standalone `intl` package with CLDR tables. |

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
| | `js/builtin/control` | `Promise` constructor, reactions (`then`, `catch`, `finally`), combinators (`all`, `race`, `allSettled`, `any`), `queueMicrotask`. |
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

# 2. Run the comprehensive regression test suite (65/65 tests)
vsc run check

# 3. Verify architectural layering rules across all 22 packages
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

### 4. Asynchronous Promises & Microtasks (§27)

Promises and microtasks run on the ECMAScript job queue, executing automatically after top-level evaluations or explicitly via `realm.RunJobs()`:

```swift
package main

import "js"

func main() -> int32 {
    let realm = js.Realm()

    let script = """
    var log = [];
    Promise.resolve("hello")
        .then(function(val) {
            log.push(val + " world");
            return 42;
        })
        .then(function(num) {
            log.push("number: " + num);
        });

    queueMicrotask(function() {
        log.push("microtask");
    });

    // Returns array of log entries collected when microtasks drained
    log.join(" | ");
    """

    // Eval evaluates script and automatically drains the microtask queue
    _ = try! realm.Eval(script)
    let outcome = try! realm.Eval("log.join(' | ');")
    print("Async trace: " + outcome.ToString())
    // Output: Async trace: hello world | microtask | number: 42
    return 0
}
```

### 5. Binary Buffers & Typed Arrays (§25)

Perform high-performance binary manipulations across `ArrayBuffer`, `DataView`, and typed arrays (`Uint8Array`, `Float32Array`, `Uint8ClampedArray`):

```swift
package main

import "js"

func main() -> int32 {
    let realm = js.Realm()

    let script = """
    // Allocate a 16-byte buffer and view as 32-bit floats
    let buffer = new ArrayBuffer(16);
    let floats = new Float32Array(buffer);
    floats[0] = 1.25;
    floats[1] = 42.5;

    // View same buffer with multi-endian DataView
    let view = new DataView(buffer);
    let firstFloat = view.getFloat32(0, true);

    // Canvas ImageData clamped pixel buffer
    let pixels = new Uint8ClampedArray(4);
    pixels[0] = 300;  // clamps to 255
    pixels[1] = -50;  // clamps to 0
    pixels[2] = 128;

    JSON.stringify({
        first: firstFloat,
        r: pixels[0],
        g: pixels[1],
        b: pixels[2]
    });
    """

    let res = try! realm.Eval(script)
    print("Binary result: " + res.ToString())
    // Output: Binary result: {"first":1.25,"r":255,"g":0,"b":128}
    return 0
}
```

### 6. Parsing, AST Inspection & Bytecode Disassembly

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

### 7. ES6 Classes & Timers (§15 & §19)

Define modern ECMAScript class hierarchies with constructor delegation, prototype method inheritance, and scheduled task timers:

```swift
package main

import "js"

func main() -> int32 {
    let realm = js.Realm()

    let script = """
    class Widget {
        constructor(title) {
            this.title = title;
        }
        render() {
            return "<widget:" + this.title + ">";
        }
        static version() {
            return "2026.1";
        }
    }

    class Button extends Widget {
        constructor(title, action) {
            super(title);
            this.action = action;
        }
        render() {
            return super.render() + " -> [Button:" + this.action + "]";
        }
    }

    let btn = new Button("Submit", "onClick");
    let isWidget = (btn instanceof Widget);
    let output = btn.render();
    let ver = Button.version(); // static method inheritance

    // Schedule delayed task via global timer
    var fired = false;
    let tid = setTimeout(function() {
        fired = true;
    }, 10);

    JSON.stringify({
        isWidget: isWidget,
        output: output,
        version: ver
    });
    """

    let res = try! realm.Eval(script)
    print("Class result: " + res.ToString())
    // Output: Class result: {"isWidget":true,"output":"<widget:Submit> -> [Button:onClick]","version":"2026.1"}
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
Run the 65-point test harness verifying lexer tokens, AST nodes, scope analysis, shapes, strings, regex, VM evaluation, GC cycles, ES6 classes, and memory primitives:
```bash
vsc run check
```

---

## License

[MIT](LICENSE)
