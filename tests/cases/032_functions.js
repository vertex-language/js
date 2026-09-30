// §15.2 function declarations/expressions, name and length.
function decl(a, b) { return a + b; }
const expr = function (a) {};
const named = function inner(a, b, c) {};
const arrow = (a, b = 1, ...c) => {};
console.log(decl.name, expr.name, named.name, arrow.name, decl.length, named.length, arrow.length);
const obj = { m() {}, ["comp" + "uted"]: function () {}, get g() { return 1; }, a: () => {} };
console.log(obj.m.name, obj.computed.name, Object.getOwnPropertyDescriptor(obj, "g").get.name, obj.a.name);
const s = Symbol("desc");
const o2 = { [s]() {} };
console.log(o2[s].name);
console.log(function () {}.name === "", (function () {}).bind().name, decl.bind(null).name);
console.log(decl(1, 2), decl("a", "b"), decl(1), (function () { return; })());
function fact(n) { return n <= 1 ? 1 : n * fact(n - 1); }
console.log(fact(10));
console.log(Object.getOwnPropertyNames(decl).sort().join(","));
console.log(Object.getOwnPropertyNames(arrow).sort().join(","));
