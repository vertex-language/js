// TypedArray.prototype methods: set, subarray, slice, from, of, sort, find, etc.
const t = new Int16Array([5, 1, 4, 2, 3]);
console.log(t.slice(1, 3).join(), t.subarray(1, 3).join(), t.map(x => x * 2) instanceof Int16Array);
const sub = t.subarray(0, 2);
sub[0] = 99;
console.log(t[0], t.slice(0, 1)[0] === 99);
console.log(t.sort().join(), new Float64Array([3, NaN, -0, 0, -Infinity]).sort().join(), t.toSorted((a, b) => b - a).join());
const u = new Uint8Array(6);
u.set([1, 2], 1); u.set(new Uint8Array([9]), 5);
console.log(u.join(), Uint8Array.from("123").join(), Uint8Array.of(1, 256).join());
try { u.set([1, 2, 3], 5); } catch (e) { console.log(e.name); }
console.log(u.indexOf(2), u.includes(9), u.reduce((a, b) => a + b), u.find(x => x > 1), u.at(-1), u.fill(7, 4).join());
console.log(Object.getPrototypeOf(Int8Array).name, Object.prototype.toString.call(u), u[Symbol.toStringTag]);
console.log(new Uint8Array([1, 2, 3]).toReversed().join(), new Uint8Array([1, 2]).with(0, 300).join());
