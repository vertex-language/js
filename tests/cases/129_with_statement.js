// §14.11 with statement (sloppy mode) and Symbol.unscopables.
const o = { a: 1, b: 2 };
with (o) { console.log(a + b); a = 10; c_global = "created"; }
console.log(o.a, typeof c_global, "c_global" in o);
const arr = [1, 2];
var values = "outer values";
with (arr) { console.log(values, length, typeof push); }
function f(obj) { with (obj) { return function () { return v; }; } }
const g = f({ v: "captured" });
console.log(g());
