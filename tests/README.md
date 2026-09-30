# tests

150 small, isolated JavaScript programs that together sweep ECMA-262 (up to
ES2026), with Node as the oracle. The target is a browser's JavaScript
foundation: the language and its built-ins, without host APIs like the DOM,
fetch, WebSocket, timers or Node's `require`/`process`. `console.log` is
the one host function a case uses.

```
cases/NNN_topic.js     one case per spec area, numbered roughly in spec order
expected/NNN_topic.out what Node prints for it
oracle.mjs             runs one case under Node as a classic script
run.sh                 builds vjs, runs the cases, compares with expected/
```

## Running

```bash
tests/run.sh             # every case
tests/run.sh regexp 09   # cases whose name contains "regexp" or "09"
tests/run.sh -v 068      # with a diff for each failure
tests/run.sh --update    # regenerate expected/ from Node
```

## Writing a case

- Keep it self-contained: no imports and no shared helpers.
- Log only primitives: strings, numbers (never `-0`), booleans, `undefined`,
  `null`. Convert everything else first with `String(x)`, `JSON.stringify`,
  or `.join()`. Engines disagree on how `console.log` formats objects, but
  never on how it formats primitives. `oracle.mjs` rejects a case that breaks
  this rule, or whose first argument contains `%`, which Node treats as a
  format string.
- Catch the errors you expect and log `e.name`. An uncaught exception fails
  the case.
- Rely only on deterministic behaviour: use the UTC methods for dates, and
  don't print random numbers or GC timing.
- Cases run as a classic `<script>`, so top-level `this` is `globalThis` and
  a top-level `var` makes a global property. Promise jobs run after the
  script.
