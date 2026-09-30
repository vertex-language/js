// §14.3.3 object destructuring: renames, defaults, nesting, computed keys.
const { a, b: renamed, c = "dflt", d: { e = 5, f } = {} } = { a: 1, b: 2, d: { f: 6 } };
console.log(a, renamed, c, e, f);
const key = "dyn";
const { [key]: dynVal, ["x" + 1]: x1 } = { dyn: "D", x1: "X" };
console.log(dynVal, x1);
const { length, 0: firstChar } = "hello";
console.log(length, firstChar);
const { toFixed } = 5;
console.log(typeof toFixed);
let p, q;
({ p, q = p * 2 } = { p: 4 });
console.log(p, q);
try { const { z } = undefined; } catch (err) { console.log(err.name); }
const { deep: { deeper: { deepest } } } = { deep: { deeper: { deepest: "found" } } };
console.log(deepest);
const order = [];
const src = { get m() { order.push("m"); return 1; }, get n() { order.push("n"); return 2; } };
const { n, m } = src;
console.log(order.join(","), m + n);
