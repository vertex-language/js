// §13.5.1 delete and §13.10.1 in operator.
const o = { a: 1, b: undefined };
console.log("a" in o, "b" in o, "c" in o, "toString" in o, 0 in [1], 1 in [1], "length" in []);
console.log(delete o.a, "a" in o, delete o.nonexistent, delete o["b"], Object.keys(o).length);
const arr = [1, 2, 3];
delete arr[1];
console.log(arr.length, 1 in arr, arr.join("|"));
var gvar = 1;
console.log(delete globalThis.gvar, typeof gvar);
globalThis.gprop = 1;
console.log(delete globalThis.gprop, typeof gprop);
try { "x" in "string"; } catch (e) { console.log(e.name); }
const sym = Symbol();
console.log(sym in { [sym]: 1 }, Symbol.iterator in [], "size" in new Map());
let local = 1;
console.log(delete local, local);
