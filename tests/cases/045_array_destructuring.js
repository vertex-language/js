// §14.3.3 array destructuring patterns.
const [a, b, c = "def", ...rest] = [1, 2, undefined, 4, 5];
console.log(a, b, c, rest.join(","));
const [, second, , fourth] = "abcd";
console.log(second, fourth);
let x = 1, y = 2;
[x, y] = [y, x];
console.log(x, y);
const [[n1, n2], [n3]] = [[1, 2], [3]];
console.log(n1 + n2 + n3);
const [m = 1, nn = m + 1] = [];
console.log(m, nn);
const [p, q] = new Set(["s1", "s2"]);
console.log(p, q);
const [first, ...others] = "héllo";
console.log(first, others.length);
try { const [z] = null; } catch (e) { console.log(e.name); }
const obj = {};
[obj.a, obj["b"]] = [10, 20];
console.log(obj.a, obj.b);
let closed = false;
const it = { [Symbol.iterator]() { return { next: () => ({ value: 1, done: false }), return() { closed = true; return {}; } }; } };
const [one] = it;
console.log(one, closed);
