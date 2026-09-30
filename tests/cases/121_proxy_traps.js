// Remaining Proxy traps and invariants.
const log = [];
const handler = {
  ownKeys(t) { log.push("ownKeys"); return ["b", "a", ...Reflect.ownKeys(t)]; },
  getOwnPropertyDescriptor(t, k) { return Reflect.getOwnPropertyDescriptor(t, k) ?? { value: k.toUpperCase(), enumerable: true, configurable: true }; },
  defineProperty(t, k, d) { log.push("define " + k); return Reflect.defineProperty(t, k, d); },
  getPrototypeOf() { return Array.prototype; },
  apply(t, thisArg, args) { return "applied:" + args.join(); },
  construct(t, args) { return { constructed: args.length }; },
};
const p = new Proxy(function () {}, handler);
console.log(Object.keys(p).join(), p instanceof Array, p(1, 2), new p(1, 2, 3).constructed);
Object.defineProperty(p, "z", { value: 1, configurable: true });
console.log(log.join(","));
const frozen = Object.freeze({ k: 1 });
const liar = new Proxy(frozen, { get() { return 2; } });
try { liar.k; } catch (e) { console.log("invariant:", e.name); }
const np = new Proxy({}, { isExtensible() { return false; } });
try { Object.isExtensible(np); } catch (e) { console.log("isExtensible invariant:", e.name); }
const pe = new Proxy({}, { preventExtensions(t) { Object.preventExtensions(t); return true; } });
console.log(Object.isExtensible(Object.preventExtensions(pe)));
try { new Proxy({}, {})(); } catch (e) { console.log("not callable:", e.name); }
console.log(typeof new Proxy(() => {}, {}), typeof new Proxy({}, {}));
