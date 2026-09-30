// oracle.mjs runs one test case under Node as a classic *script* (not a
// CommonJS module), so top-level `this`, `var` and function declarations
// behave as they do in a browser <script>. It prints what the case logs.
//
// It also enforces the one rule the cases follow so that any conforming
// engine's console.log prints byte-for-byte the same thing: every logged
// argument is a string, number (never -0), boolean, undefined or null.
// Objects, symbols and bigints must be converted first (String, JSON, join).
//
//     node tests/oracle.mjs tests/cases/001_number_literals.js
import fs from "node:fs";
import vm from "node:vm";

const file = process.argv[2];
const source = fs.readFileSync(file, "utf8");

const real = console.log;
const fail = (msg) => {
  process.stderr.write(`oracle: ${file}: ${msg}\n`);
  process.exitCode = 3;
};
console.log = (...args) => {
  args.forEach((a, i) => {
    const t = typeof a;
    const ok = a === null || t === "undefined" || t === "string" || t === "boolean" ||
      (t === "number" && !Object.is(a, -0));
    if (!ok) fail(`argument ${i} is not a printable primitive (${t})`);
    if (i === 0 && t === "string" && a.includes("%")) fail("first argument contains '%'");
  });
  real(...args);
};

process.on("unhandledRejection", (e) => fail(`unhandled rejection: ${e}`));
try {
  vm.runInThisContext(source, { filename: file });
} catch (e) {
  real(`Uncaught ${e && e.name}: ${e && e.message}`);
  fail("uncaught exception");
}
