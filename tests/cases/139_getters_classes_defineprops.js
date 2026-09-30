// Accessor inheritance, shadowing and property lookup along the prototype chain.
class Temp {
  #c = 0;
  get f() { return this.#c * 1.8 + 32; }
  set f(v) { this.#c = (v - 32) / 1.8; }
  get c() { return this.#c; }
}
const t = new Temp();
t.f = 212;
console.log(t.c, t.f, Object.keys(t).length, "f" in t, t.hasOwnProperty("f"));
const proto = { set x(v) { this.store = v * 2; } };
const child = Object.create(proto);
child.x = 5;
console.log(child.store, child.hasOwnProperty("x"));
const roProto = Object.create(Object.defineProperty({}, "ro", { value: 1, writable: false }));
roProto.ro = 2;
console.log(roProto.ro, roProto.hasOwnProperty("ro"));
Object.defineProperty(roProto, "ro", { value: 3 });
console.log(roProto.ro);
