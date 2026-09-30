// §13.13 ?? and §13.3.9 optional chaining.
console.log(null ?? "d", undefined ?? "d", 0 ?? "d", "" ?? "d", false ?? "d", NaN ?? "d");
const o = { a: { b: { c: 1 } }, f() { return "called"; }, arr: [10, 20] };
console.log(o?.a?.b?.c, o.x?.y, o.x?.y.z.w, o.f?.(), o.g?.(), o.arr?.[1], o.nope?.[0]);
let calls = 0;
const n = null;
n?.[calls++];
n?.m(calls++);
console.log(calls);
console.log((null)?.x ?? "fallback", typeof o?.f);
const deep = { x: null };
console.log(deep.x?.y.z, delete o?.a, "a" in o);
console.log((o.q ?? o.arr)[0], (0 || null) ?? "z");
