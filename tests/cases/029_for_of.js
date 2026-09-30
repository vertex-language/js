// §14.7.5 for-of over arrays, strings (code points), maps, sets, arguments.
const r = [];
for (const x of [1, 2, 3]) r.push(x * 2);
console.log(r.join(","));
const cps = [];
for (const ch of "a😀b") cps.push(ch.length);
console.log(cps.join(","));
for (const [k, v] of new Map([["x", 1], ["y", 2]])) console.log(k, v);
for (const v of new Set(["s1", "s2"])) console.log(v);
(function () { for (const a of arguments) console.log("arg", a); })(7, 8);
const holes = [];
for (const h of [1, , 3]) holes.push(h);
console.log(holes.join("|"));
try { for (const x of {}) {} } catch (e) { console.log(e.name); }
let t = 0;
for (let x of [1, 2]) { x = 10; t += x; }
console.log(t);
