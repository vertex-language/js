// §14.7.5 for-in: enumerable string keys, prototype chain, ordering.
const proto = { inherited: 1 };
const o = Object.create(proto);
o.b = 1; o[2] = 1; o.a = 1; o[1] = 1; o[Symbol("s")] = 1;
Object.defineProperty(o, "hidden", { value: 1, enumerable: false });
const keys = [];
for (const k in o) keys.push(k);
console.log(keys.join(","));
const arr = ["x", "y"];
arr.extra = true;
const ak = [];
for (const i in arr) ak.push(i + typeof i);
console.log(ak.join(","));
let cnt = 0;
for (const k in null) cnt++;
for (const k in undefined) cnt++;
for (const k in "hi") cnt++;
console.log(cnt);
const del = { a: 1, b: 2, c: 3 };
const seen = [];
for (const k in del) { seen.push(k); delete del.b; }
console.log(seen.join(","));
