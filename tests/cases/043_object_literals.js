// §13.2.5 object initializers: shorthand, methods, computed keys, __proto__, duplicates.
const x = 1, y = 2;
const i = 0;
const o = {
  x, y,
  m() { return "method"; },
  ["k" + (i + 1)]: "computed",
  [`t${2}`]: "template",
  1.5: "num key", 0x10: "hex key",
  "quoted key": true,
  dup: 1, dup: 2,
};
console.log(o.x + o.y, o.m(), o.k1, o.t2, o["1.5"], o[16], o["quoted key"], o.dup);
console.log(Object.keys(o).join(","));
const p = { __proto__: { inherited: "yes" }, own: 1 };
console.log(p.inherited, Object.keys(p).join(","));
const q = { ["__proto__"]: 5 };
console.log(Object.keys(q).join(","), Object.getPrototypeOf(q) === Object.prototype);
const z = { async am() {}, *gm() {}, async *agm() {} };
console.log(Object.prototype.toString.call(z.am), typeof z.gm().next);
try { new o.m(); } catch (e) { console.log("method not ctor:", e.name); }
