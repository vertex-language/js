# js

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![js: ecmascript-engine](https://img.shields.io/badge/js-ecmascript--engine-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/js)
[![tests: 149/150 passing](https://img.shields.io/badge/tests-149%2F150%20passing-10b981?style=flat-square&labelColor=e4e4e7)](tests/)

A JavaScript engine in pure Vertex: a parser, a scope analyzer, a
bytecode compiler, an interpreter and the ECMAScript built-ins. It is the
language a browser runs, without the browser -- no DOM, no fetch, no
timers -- so a host adds what it needs on top: a terminal (`vjs`), or
the `ui` web view.

The target is ECMA-262 as of ES2026. Node is the oracle the tests are
checked against; the goal is a browser's foundation, not Node's APIs.

---

## Status

`tests/` holds 150 small programs that sweep the specification, each
compared with what Node prints. 149 pass. The one that does not needs
`Intl` (ECMA-402), which is not implemented.

| Area | |
| :--- | :--- |
| Syntax | ES2026: classes with private members and static blocks, generators, async functions and generators, destructuring, optional chaining, logical assignment, `using` and `await using`, hashbang, numeric separators. Scripts; modules parse but do not load yet. |
| Built-ins | `Object`, `Function`, `Symbol`, the errors (with `AggregateError` and `SuppressedError`), `Number`, `Math`, `BigInt`, `Date`, `String`, `RegExp`, `Array`, the typed arrays, `ArrayBuffer`, `SharedArrayBuffer`, `DataView`, `Atomics`, `Map`, `Set`, `WeakMap`, `WeakSet`, `WeakRef`, `FinalizationRegistry`, `JSON`, `Promise`, the iterator helpers, `Proxy`, `Reflect`, `DisposableStack`, `AsyncDisposableStack`, `globalThis`, `eval`. |
| Host | `queueMicrotask` is installed by the runtime; `console` by `Runtime.DefineConsole`. |
| Missing | `Intl`; module loading; a tracing collector (see Memory below). |

---

## Using it

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
        rt.RunJobs()                       // promise jobs the script queued
        print(try object.ToString(v).String) // 42
        return 0
    } catch let e as js.Exception {
        print("Uncaught \(e.Message)")     // `Name: message`, as V8 prints it
        return 1
    } catch {
        return 1
    }
}
```

A `Runtime` is an agent and one realm with every built-in installed.
`Evaluate` runs a script and returns its completion value; `RunJobs`
drains the microtask queue; `Call` calls a function value; `Define` and
`Function` add host globals. `Agent.OnJobError` and
`Agent.OnRejectionTracker` report what a browser's console would: an
exception out of a job, and a promise rejected with no handler.

---

## Commands

```bash
vsc run ./cmd/vjs -- file.js      # run a file, as `node file.js` would
vsc run ./cmd/repl                # read, evaluate, print
vsc run ./cmd/dis -- file.js      # the bytecode a file compiles to
vsc run ./cmd/parse -- file.js    # the front end alone: syntax errors
vsc run ./cmd/example             # embedding, end to end
vsc run ./cmd/check-deps          # the layering below, checked against the imports
tests/run.sh                      # the conformance programs (see tests/README.md)
```

---

## Packages

The front end knows nothing of the runtime, the built-ins know nothing of
the interpreter, and nothing imports the web; `cmd/check-deps` enforces it.

| Package | |
| :--- | :--- |
| `js/token`, `js/scanner` | Tokens and the lexer: UTF-8 source, numeric literals, templates, regular expression literals, automatic semicolon insertion. |
| `js/ast`, `js/parser` | The syntax tree and a recursive-descent parser with cover grammars and the early errors. |
| `js/scope` | Bindings: hoisting, the temporal dead zone, which names closures capture (context slots) and which stay in registers, direct `eval`. |
| `js/printer` | A syntax tree back to source. |
| `js/bytecode`, `js/codegen` | A register-and-accumulator instruction set (after V8's Ignition) and the compiler to it. `finally`, iterator closing and `using` disposal unwind through one control stack. |
| `js/str`, `js/value` | UTF-16 strings, property keys, numbers (conversions, shortest round-trip printing), BigInt. |
| `js/object` | Objects and their internal methods (§10), the realm and intrinsics, promises and the job queue, and the abstract operations (§7) the rest is written in. |
| `js/interp` | The interpreter: frames, generators and async functions, `eval` and `new Function`. |
| `js/regexp/syntax`, `js/regexp` | Regular expressions: an ES2025 parser (named groups, lookbehind, modifiers, `\p{…}`, the `v` flag's set notation, Annex B without `u`) and a backtracking matcher over UTF-16. |
| `js/builtin/*` | The built-ins, by chapter: `global`, `fundamental`, `numeric`, `text`, `indexed`, `keyed`, `structured`, `memory`, `control`, `reflection`. |
| `js` | The embedding API: `Runtime` and `Exception`. |

---

## Design notes

- **Calls do not use the native stack.** A call from bytecode to bytecode
  pushes a frame on the interpreter's own stack, so recursion is as deep
  as `Engine.MaxDepth` (10,000) on any thread, a worker's small stack
  included. A built-in calling back into JavaScript (`map`, a getter)
  does nest natively; `Engine.StackLimit` bounds the bytes that may use
  (1 MB by default) and a host on a thread with a larger or smaller stack
  sets it.
- **Some built-ins are written in JavaScript.** `Realm.SelfHosted` compiles
  a built-in from JavaScript while the realm is made, before any script,
  with native helpers for the spec's abstract operations; its functions
  show `[native code]`. `Array.fromAsync` and the disposable stacks are.
- **Regular expressions** run on a backtracking virtual machine with its
  own stack, so a long input cannot overflow the native one. It is
  correct against V8 and slower than V8's compiled matcher on patterns
  that backtrack heavily.
- **Memory.** Objects are reference counted, as Vertex's are, so a cycle
  of JavaScript objects is not reclaimed, and `WeakRef`, `WeakMap` and
  `FinalizationRegistry` hold what they hold strongly (which the
  specification allows). A tracing collector of the engine's own is the
  next piece of the runtime.

---

## License

MIT; see [LICENSE](LICENSE).
