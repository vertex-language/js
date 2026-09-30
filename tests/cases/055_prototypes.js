// §10.1 [[GetPrototypeOf]]/[[SetPrototypeOf]], Object.create, prototype chains.
const animal = { eats: true, walk() { return "walk " + this.name; } };
const rabbit = Object.create(animal, { name: { value: "Bun", enumerable: true } });
console.log(rabbit.eats, rabbit.walk(), Object.getPrototypeOf(rabbit) === animal);
console.log(animal.isPrototypeOf(rabbit), Object.prototype.isPrototypeOf(rabbit));
const bare = Object.create(null);
console.log(typeof bare.toString, Object.getPrototypeOf(bare));
Object.setPrototypeOf(bare, { hello: "hi" });
console.log(bare.hello);
const o = {};
o.__proto__ = animal;
console.log(o.eats, o.__proto__ === animal);
try { Object.setPrototypeOf(animal, rabbit); } catch (e) { console.log("cycle:", e.name); }
function Ctor() {}
console.log(Ctor.prototype.constructor === Ctor, Object.getPrototypeOf(Ctor) === Function.prototype);
console.log(Object.getPrototypeOf(Object.prototype), Object.getPrototypeOf(Function.prototype) === Object.prototype);
rabbit.eats = false;
console.log(rabbit.eats, animal.eats);
const ne = Object.preventExtensions({});
try { Object.setPrototypeOf(ne, {}); } catch (e) { console.log("non-ext:", e.name); }
console.log(Reflect.setPrototypeOf(ne, {}), Reflect.setPrototypeOf(ne, Object.prototype));
