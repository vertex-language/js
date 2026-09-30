// §24.1 Map: SameValueZero keys, insertion order, iteration, size.
const m = new Map();
const objKey = {}, fnKey = () => {};
m.set("s", 1).set(1, "num").set(objKey, "obj").set(fnKey, "fn").set(NaN, "nan").set(-0, "zero");
console.log(m.size, m.get("s"), m.get(1), m.get("1"), m.get(objKey), m.get({}), m.get(NaN), m.get(0), m.get(fnKey));
console.log([...m.keys()].map(k => typeof k).join());
m.delete(1);
console.log(m.has(1), m.size, m.delete("missing"));
m.set("s", "updated");
console.log([...m.values()][0]);
const order = [];
m.forEach((v, k, map) => order.push(typeof k === "string" ? k : typeof k));
console.log(order.join(), map_is_same(m));
function map_is_same(x) { let s = null; x.forEach((v, k, mm) => s = mm === x); return s; }
m.clear();
console.log(m.size);
const it = new Map([["a", 1]]);
const iter = it.entries();
it.set("b", 2);
console.log([...iter].length);
try { Map(); } catch (e) { console.log(e.name); }
console.log(new Map([[1, 2], [1, 3]]).get(1), Object.prototype.toString.call(new Map()));
