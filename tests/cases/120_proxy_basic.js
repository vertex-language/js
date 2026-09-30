// §28.2 Proxy get/set/has/deleteProperty traps.
const log = [];
const target = { a: 1 };
const p = new Proxy(target, {
  get(t, k, r) { log.push("get " + String(k)); return k in t ? Reflect.get(t, k, r) : "default"; },
  set(t, k, v) { log.push("set " + k); t[k] = v * 2; return true; },
  has(t, k) { return k.startsWith("x") || k in t; },
  deleteProperty(t, k) { log.push("delete " + k); return delete t[k]; },
});
p.b = 5;
console.log(p.a, p.b, p.missing, "xyz" in p, "a" in p, "q" in p);
delete p.a;
console.log(target.a, log.join(","));
const passthrough = new Proxy({ z: 1 }, {});
passthrough.y = 2;
console.log(passthrough.z + passthrough.y, Object.keys(passthrough).join());
const strictFail = new Proxy({}, { set() { return false; } });
strictFail.x = 1;
try { (function () { "use strict"; strictFail.x = 1; })(); } catch (e) { console.log(e.name); }
const { proxy, revoke } = Proxy.revocable({}, {});
revoke();
try { proxy.x; } catch (e) { console.log(e.name); }
