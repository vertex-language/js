// §19 global object: globalThis, value properties, var/function globals.
var gv = "global var";
function gf() {}
let gl = "global let";
console.log(typeof globalThis, globalThis.gv, typeof globalThis.gf, globalThis.gl, "gl" in globalThis);
console.log(globalThis.globalThis === globalThis, this === globalThis);
console.log(Object.getOwnPropertyDescriptor(globalThis, "gv").configurable, Object.getOwnPropertyDescriptor(globalThis, "NaN").writable);
NaN = 1; undefined = 2; Infinity = 3;
console.log(NaN, undefined, Infinity);
globalThis.dyn = "dynamic";
console.log(dyn, delete globalThis.dyn, typeof dyn);
console.log(isNaN("abc"), isNaN("12"), isFinite("12"), isFinite(Infinity), isNaN(undefined), isFinite(null));
console.log(["Object", "Array", "Promise", "Proxy", "Reflect", "JSON", "Math", "Atomics", "Intl"].map(n => typeof globalThis[n]).join());
