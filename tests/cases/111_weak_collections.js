// §24.3-24.4 WeakMap and WeakSet.
const wm = new WeakMap();
const k1 = {}, k2 = function () {};
wm.set(k1, "one").set(k2, "two");
console.log(wm.get(k1), wm.has(k2), wm.get({}), wm.delete(k1), wm.has(k1));
try { wm.set("str", 1); } catch (e) { console.log(e.name); }
try { wm.set(Symbol.for("registered"), 1); } catch (e) { console.log("registered symbol:", e.name); }
const sym = Symbol("unregistered");
wm.set(sym, "symbol key");
console.log(wm.get(sym));
const ws = new WeakSet([k1]);
console.log(ws.has(k1), ws.add(k2) === ws, ws.has(k2), ws.delete(k2), ws.has(k2));
try { ws.add(1); } catch (e) { console.log(e.name); }
console.log(typeof wm.size, typeof ws.forEach, typeof WeakMap.prototype[Symbol.iterator]);
const priv = new WeakMap();
class Person { constructor(n) { priv.set(this, { n }); } get name() { return priv.get(this).n; } }
console.log(new Person("Grace").name);
