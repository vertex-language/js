// Common real-world patterns: event emitter, debounce-free pub/sub, observer via Proxy.
class Emitter {
  #handlers = new Map();
  on(ev, fn) { (this.#handlers.get(ev) ?? this.#handlers.set(ev, []).get(ev)).push(fn); return () => this.off(ev, fn); }
  off(ev, fn) { const l = this.#handlers.get(ev); if (l) l.splice(l.indexOf(fn), 1); }
  emit(ev, ...args) { for (const fn of [...(this.#handlers.get(ev) ?? [])]) fn(...args); }
}
const em = new Emitter();
const out = [];
const off = em.on("msg", (a, b) => out.push(a + b));
em.on("msg", a => out.push("second " + a));
em.emit("msg", 1, 2);
off();
em.emit("msg", 3, 4);
console.log(out.join(" | "));
function observable(target, cb) {
  return new Proxy(target, { set(t, k, v) { const old = t[k]; t[k] = v; cb(k, old, v); return true; } });
}
const changes = [];
const state = observable({ count: 0 }, (k, o, n) => changes.push(`${k}:${o}->${n}`));
state.count++; state.count++; state.label = "x";
console.log(changes.join(", "));
