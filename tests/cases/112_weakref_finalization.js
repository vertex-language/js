// §26 WeakRef and FinalizationRegistry (API surface only; collection timing is not observable).
const target = { v: "alive" };
const ref = new WeakRef(target);
console.log(ref.deref() === target, ref.deref().v, Object.prototype.toString.call(ref));
try { new WeakRef(1); } catch (e) { console.log(e.name); }
const reg = new FinalizationRegistry(held => console.log("finalized", held));
const token = {};
console.log(reg.register({}, "held", token), reg.unregister(token), reg.unregister({}));
try { reg.register(target, target); } catch (e) { console.log(e.name); }
console.log(Object.prototype.toString.call(reg));
