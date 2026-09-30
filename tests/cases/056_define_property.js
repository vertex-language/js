// §10.1.6 [[DefineOwnProperty]] and property attributes.
const o = {};
Object.defineProperty(o, "ro", { value: 1 });
o.ro = 2;
const d = Object.getOwnPropertyDescriptor(o, "ro");
console.log(o.ro, d.writable, d.enumerable, d.configurable);
try { Object.defineProperty(o, "ro", { value: 3 }); } catch (e) { console.log(e.name); }
Object.defineProperty(o, "ro", { value: 1 });
console.log("same value redefinition ok");
Object.defineProperty(o, "acc", { get() { return "got"; }, enumerable: true, configurable: true });
console.log(o.acc, Object.keys(o).join(","));
Object.defineProperty(o, "acc", { value: "now data" });
console.log(o.acc, Object.getOwnPropertyDescriptor(o, "acc").writable);
try { Object.defineProperty(o, "bad", { value: 1, get() {} }); } catch (e) { console.log(e.name); }
Object.defineProperties(o, { p1: { value: "a", enumerable: true }, p2: { value: "b" } });
console.log(Object.keys(o).join(","), o.p2);
const all = Object.getOwnPropertyDescriptors({ x: 1, get y() { return 2; } });
console.log(Object.keys(all).join(","), all.x.writable, typeof all.y.get);
const w = Object.defineProperty({}, "w", { value: 1, writable: true, configurable: false });
Object.defineProperty(w, "w", { writable: false });
try { Object.defineProperty(w, "w", { writable: true }); } catch (e) { console.log("rewrite:", e.name); }
