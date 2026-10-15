# js

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![ecmascript: 2026](https://img.shields.io/badge/ecmascript-2026-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://tc39.es/ecma262/)
[![tests: 149/150](https://img.shields.io/badge/tests-149%2F150-10b981?style=flat-square&labelColor=e4e4e7)](tests/)

A JavaScript engine in pure Vertex: a parser, a scope analyzer, a bytecode
compiler, an interpreter, and the built-ins of ECMA-262 as of ES2026. It is
the language a browser runs without the browser -- no DOM, no fetch, no
timers -- for a host to build on: a terminal (`vjs`), or the `ui` web view.

Node is the oracle the tests are checked against. The target is a
browser's foundation, not Node's APIs.

---

## Packages

The front end knows nothing of the runtime, the built-ins know nothing of
the interpreter, and nothing imports the web; `check-deps` enforces it
against the imports themselves.

| Package | What it is |
| :--- | :--- |
| **`js`** | The embedding API: `Runtime` and `Exception`. |
| **`js/token`**, **`js/scanner`** | Tokens and the lexer: UTF-8 source, numeric literals, templates, regular expression literals, automatic semicolon insertion. |
| **`js/ast`**, **`js/parser`** | The syntax tree, and a recursive-descent parser with the cover grammars and early errors. |
| **`js/scope`** | Bindings: hoisting, the temporal dead zone, which names closures capture (context slots) and which stay in registers, direct `eval`. |
| **`js/printer`** | A syntax tree back to source. |
| **`js/bytecode`**, **`js/codegen`** | A register-and-accumulator instruction set, after V8's Ignition, and the compiler to it. `finally`, iterator closing and `using` disposal unwind through one control stack. |
| **`js/str`**, **`js/value`** | UTF-16 strings; property keys, the well-known symbols, numbers (conversions, shortest round-trip printing) and BigInt. |
| **`js/object`** | Objects and their internal methods (§10), realms and intrinsics, promises and the job queue, and the abstract operations (§7) the rest is written in. |
| **`js/interp`** | The interpreter: frames, generators and async functions, `eval` and `new Function`. |
| **`js/regexp/syntax`**, **`js/regexp`** | Regular expressions: an ES2025 parser (named and duplicate groups, lookbehind, modifiers, `\p{…}`, the `v` flag's set notation, Annex B without `u`) and a backtracking matcher over UTF-16. |
| **`js/builtin/*`** | The built-ins, by chapter: `global`, `fundamental`, `numeric`, `text`, `indexed`, `keyed`, `structured`, `memory`, `control`, `reflection`. |

It depends on `unicode` (identifiers, case mapping, `\p{…}`,
normalization), `math/big` (BigInt), `time` (`Date`), and `fs` for the
commands.

---

## Quick Start

```vertex
import (
    "js"
    "js/object"
)

func main() -> int32 {
    let rt = js.Runtime()
    rt.DefineConsole { line in print(line) }
    rt.Define("hostAdd", .object(rt.Function("hostAdd", 2) { _, args, _ in
        return .number(try object.ToNumber(object.Arg(args, 0)) + object.ToNumber(object.Arg(args, 1)))
    }))
    do {
        let v = try rt.Evaluate("console.log('sum', hostAdd(1, 2)); 6 * 7")
        rt.RunJobs()                         // the promise jobs the script queued
        print(try object.ToString(v).String) // 42
        return 0
    } catch let e as js.Exception {
        print("Uncaught \(e.Message)")       // `Name: message`, as V8 prints it
        return 1
    } catch {
        return 1
    }
}
```

A `Runtime` is an agent and one realm with every built-in installed:

| | |
| :--- | :--- |
| `Evaluate(source, filename:)` | Runs a script; its completion value, or a `js.Exception`. |
| `Compile(source, filename:)` | Parses and compiles without running; a syntax error is a `js.Exception` holding the `SyntaxError`. |
| `RunJobs()`, `HasJobs` | Drains the microtask queue; whether jobs are waiting. |
| `Call(f, this:, args)` | Calls a function value. |
| `Define(name, value)`, `Function(name, length, fn)`, `StringValue(s)` | Host globals and native functions. |
| `DefineConsole(write)` | A `console` whose `log`, `info`, `warn`, `error` and `debug` hand each line to the host. |
| `Global`, `Realm`, `Agent`, `Engine` | The pieces, for what the API above does not cover. |

`queueMicrotask` is installed by the runtime. `Agent.OnJobError` and
`Agent.OnRejectionTracker` tell a host what a browser's console reports:
an exception out of a job, and a promise rejected with no handler.

---

## Coverage

| Area | |
| :--- | :--- |
| Syntax | ES2026: classes with private members and static blocks, generators, async functions and generators, destructuring, optional chaining, logical assignment, `using` and `await using`, hashbang comments, numeric separators. Scripts; modules parse, but nothing loads them yet. |
| Built-ins | `Object`, `Function`, `Symbol`, `Boolean`, the errors (with `AggregateError` and `SuppressedError`), `Number`, `Math`, `BigInt`, `Date`, `String`, `RegExp`, `Array`, the typed arrays, `ArrayBuffer`, `SharedArrayBuffer`, `DataView`, `Atomics`, `Map`, `Set`, `WeakMap`, `WeakSet`, `WeakRef`, `FinalizationRegistry`, `JSON`, `Promise`, `Iterator` and its helpers, `Proxy`, `Reflect`, `DisposableStack`, `AsyncDisposableStack`, `globalThis`, `eval`. |
| Missing | `Intl` (ECMA-402); module loading; a tracing collector (see Memory, below). |

---

## Design

- **Calls do not use the native stack.** A call or `new` from bytecode to
  bytecode pushes a frame on the interpreter's own stack, so recursion
  goes as deep as `Engine.MaxDepth` (10,000) on any thread, a worker's
  small stack included. A built-in calling back into JavaScript (`map`, a
  getter) does nest natively: `Engine.StackLimit` bounds the bytes that
  may take (1 MB by default), and a host on a thread with a larger or
  smaller stack sets it.
- **Some built-ins are written in JavaScript.** `Realm.SelfHosted` compiles
  one from JavaScript while the realm is made, before any script runs,
  with native helpers for the spec's abstract operations; its functions
  show `[native code]`. `Array.fromAsync` and the disposable stacks are.
- **Regular expressions** run on a backtracking virtual machine with its
  own stack, so a long input cannot overflow the native one. It agrees
  with V8, and is slower than V8's compiled matcher on patterns that
  backtrack heavily.
- **Memory.** Objects are reference counted, as Vertex's are, so a cycle
  of JavaScript objects is not reclaimed, and `WeakRef`, `WeakMap` and
  `FinalizationRegistry` hold what they hold strongly, which the
  specification allows. A tracing collector of the engine's own is the
  next piece of the runtime.

---

## Commands

```bash
vsc run vjs -- file.js      # run a file, as `node file.js` would
vsc run repl                # read, evaluate, print
vsc run dis -- file.js      # the bytecode a file compiles to
vsc run parse -- file.js    # the front end alone: the first syntax error
vsc run example             # embedding, end to end
```

---

## Testing

```bash
tests/run.sh
vsc run check-deps
```

`tests/` holds 150 small programs that sweep the specification, one area
each, with the output Node prints for each checked in beside it;
`tests/run.sh` builds `vjs`, runs them all and compares. 149 pass: the
one that does not needs `Intl`. `tests/README.md` has the rules a
program follows so that any conforming engine prints the same thing.
`check-deps` reads every package's imports and checks them against the
layering above.

---

## License

[MIT](LICENSE).
