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

`proposed_js_package.md` (on the Desktop) has the full plan. In short:

| Group | Packages |
| :--- | :--- |
| Front end (like Go's `go/token`, `go/scanner`, `go/ast`, `go/parser`) | `js/token`, `js/scanner`, `js/ast`, `js/parser`, `js/scope`, `js/printer` |
| Bytecode | `js/bytecode`, `js/codegen` |
| Runtime | `js/value` (NaN-boxed), `js/str` (UTF-16 strings, ropes, atoms), `js/object` (shapes, properties), `js/ic` (inline caches), `js/interp`, `js/module` |
| Built-ins, by ECMA-262 chapter | `js/builtin/global`, `fundamental`, `numeric`, `text`, `indexed`, `keyed`, `structured`, `memory`, `control`, `reflection`, later `intl` |
| Regular expressions | `js/regexp/syntax`, `js/regexp` |
| Embedding | `js`: `Agent`, `Realm`, `Value`, `Eval`, and the host hooks |

It builds on other repositories rather than copying them: `gc` (the traced heap),
`text/unicode`, `text/norm` and `text/strconv`, `math/big` (BigInt), `time/zone`
(Date), and later `intl`.

`cmd/test262` runs the ECMAScript conformance suite and prints a pass count
per feature directory: progress is a number. `cmd/repl`, `cmd/dis`,
`cmd/fuzz`, `cmd/bench`, and `cmd/check`, the offline test program.

---

## Order

1. The front end, to test262's parser tests.
2. `gc`, the runtime and the built-ins, to test262's language and built-ins,
   with the host hooks stubbed.
3. `web/script` in the `web` repository: WebIDL bindings, the HTML event
   loop, `<script>`.
4. Speed without a JIT: off-main-thread compiling, a bytecode cache, a
   generational GC.

An interpreter is the engine. Machine code (`isa`, `jit`) comes only if
measurements on real sites ask for it, and only after the web engine
isolates sites in processes of their own.

---

## License

[MIT](LICENSE)
