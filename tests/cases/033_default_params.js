// §15.1 default parameter values and their scope.
function f(a, b = 2, c = a + b) { return [a, b, c].join(","); }
console.log(f(1), f(1, undefined, 5), f(1, null), f());
let calls = 0;
function g(x = ++calls) { return x; }
g(); g(1); g();
console.log(calls);
function h(a, b = () => a) { a = "changed"; return b(); }
console.log(h("orig"));
try { (function (a = b, b) {})(); } catch (e) { console.log(e.name); }
function len(a, b = 1, c) {}
console.log(len.length);
const arrow = ({ x = 1, y } = {}) => x + (y ?? 0);
console.log(arrow(), arrow({ y: 5 }), arrow({ x: 10, y: 1 }));
