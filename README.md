# js

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![status: planned](https://img.shields.io/badge/status-planned-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/js)

The JavaScript language in pure Vertex: a parser, a bytecode compiler, an
interpreter with its own tracing heap, and the built-ins. Nothing here
knows about web pages. A host plugs in through ECMAScript's host hooks
(the job queue, module loading, what a realm's global object holds), as
V8 and SpiderMonkey sit apart from the engines that embed them.

The web engine uses it through one optional package, `web/script`. A
program that never imports `web/script` -- a `.vsx` app, a docs viewer, a
PDF renderer -- links none of this.

---

## Packages (planned)

| Package | What it is |
| :--- | :--- |
| **`js/syntax`** | The lexer, the parser, the AST and early errors, for ES2025. |
| **`js/compile`** | Scope analysis, and the AST to bytecode. |
| **`js/vm`** | The bytecode interpreter: values, objects and their shapes, inline caches, and a tracing collector for the JS heap. |
| **`js/builtins`** | `Object`, `Function`, `Array`, `Promise`, `Map`, `Set`, typed arrays, `JSON`, `Date`, `Proxy`, `Reflect`, and the rest of the standard library. |
| **`js/regexp`** | The ECMAScript regular expression engine. |
| **`js`** | The front door: `Realm`, `Value`, `Eval`, modules, and the host hooks. |

`cmd/test262` runs the ECMAScript conformance suite and prints a pass
count per feature directory: progress is a number. `cmd/repl` evaluates
lines. `cmd/check` is the offline test program, as in every repository.

---

## Order

1. `js/syntax` and `js/compile`, to test262's parser tests.
2. `js/vm` and `js/builtins`, to test262's language and built-ins, with
   the host hooks stubbed.
3. `web/script` in the `web` repository: WebIDL bindings, the HTML event
   loop, `<script>`.

No JIT until the web engine can isolate a site's pages in a process of
their own. `proposed_webview.md` has the reasons.

---

## License

[MIT](LICENSE)
