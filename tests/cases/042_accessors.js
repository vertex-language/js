// §13.2.5 getters and setters in object literals.
const temp = {
  _c: 25,
  get f() { return this._c * 9 / 5 + 32; },
  set f(v) { this._c = (v - 32) * 5 / 9; },
};
console.log(temp.f);
temp.f = 212;
console.log(temp._c);
const ro = { get only() { return "r"; } };
ro.only = "w";
console.log(ro.only);
const wo = { set only(v) { this.stored = v; } };
wo.only = 5;
console.log(wo.only, wo.stored);
const d = Object.getOwnPropertyDescriptor(temp, "f");
console.log(typeof d.get, typeof d.set, d.enumerable, d.configurable, "value" in d);
const child = Object.create(temp);
child.f = 32;
console.log(child._c, temp._c, child.hasOwnProperty("_c"));
