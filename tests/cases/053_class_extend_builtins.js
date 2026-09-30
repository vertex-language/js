// Subclassing built-ins: Array, Error, Map, Promise.
class Stack extends Array {
  peek() { return this[this.length - 1]; }
}
const s = new Stack();
s.push(1, 2, 3);
console.log(s.length, s.peek(), Array.isArray(s), s instanceof Stack);
const mapped = s.map(x => x * 2);
console.log(mapped instanceof Stack, mapped.peek());
class HttpError extends Error {
  constructor(status, msg) { super(msg); this.name = "HttpError"; this.status = status; }
}
const e = new HttpError(404, "not found");
console.log(e instanceof Error, e.name, e.message, e.status, String(e));
class DefaultMap extends Map {
  constructor(def) { super(); this.def = def; }
  get(k) { return this.has(k) ? super.get(k) : this.def; }
}
const dm = new DefaultMap(0);
dm.set("a", 5);
console.log(dm.get("a"), dm.get("b"), dm.size);
class MyP extends Promise {}
const mp = MyP.resolve(1).then(v => v);
console.log(mp instanceof MyP);
