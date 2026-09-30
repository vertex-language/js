// §28.1 Reflect namespace.
const o = { a: 1 };
console.log(Reflect.has(o, "a"), Reflect.get(o, "a"), Reflect.set(o, "b", 2), o.b, Reflect.ownKeys(o).join());
console.log(Reflect.defineProperty(o, "c", { value: 3 }), Reflect.defineProperty(Object.freeze({}), "x", { value: 1 }));
console.log(Reflect.deleteProperty(o, "a"), Reflect.getPrototypeOf(o) === Object.prototype, Reflect.isExtensible(o), Reflect.preventExtensions(o), Reflect.isExtensible(o));
console.log(Reflect.apply(Math.max, null, [1, 3, 2]), Reflect.construct(Date, [0]).getTime(), Reflect.getOwnPropertyDescriptor({ x: 1 }, "x").value);
const recv = { factor: 10 };
const withGetter = { get val() { return this.factor; } };
console.log(Reflect.get(withGetter, "val", recv));
try { Reflect.get(1, "x"); } catch (e) { console.log(e.name); }
console.log(Object.prototype.toString.call(Reflect), typeof Reflect);
class A { constructor() { this.nt = new.target.name; } } class B {}
console.log(Reflect.construct(A, [], B).nt, Reflect.construct(A, [], B) instanceof B);
