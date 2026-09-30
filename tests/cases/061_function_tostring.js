// §20.2.3.5 Function.prototype.toString returns the source text slice.
function add(a, b) { return a + b; }
console.log(add.toString());
const arrow = (x) => x * 2;
console.log(String(arrow));
class A { m() { return 1; } }
console.log(A.toString());
console.log(A.prototype.m.toString());
const o = { get g() { return 1; } };
console.log(Object.getOwnPropertyDescriptor(o, "g").get.toString());
console.log(/\{\s*\[native code\]\s*\}/.test(Math.max.toString()), /native code/.test(add.bind(null).toString()));
