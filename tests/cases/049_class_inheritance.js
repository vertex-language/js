// §15.7 extends, super calls, super property access, method overriding.
class Animal {
  constructor(name) { this.name = name; }
  speak() { return `${this.name} makes a sound`; }
  static create(n) { return new this(n); }
}
class Dog extends Animal {
  constructor(name, breed) { super(name); this.breed = breed; }
  speak() { return super.speak() + " (woof)"; }
}
const d = new Dog("Rex", "lab");
console.log(d.speak(), d.breed, d instanceof Animal, d instanceof Dog);
console.log(Dog.create("Pup") instanceof Dog, Object.getPrototypeOf(Dog) === Animal);
class NoCtor extends Animal {}
console.log(new NoCtor("auto").name);
class Bad extends Animal { constructor() { this.x = 1; } }
try { new Bad(); } catch (e) { console.log(e.name); }
class Forgot extends Animal { constructor() {} }
try { new Forgot(); } catch (e) { console.log(e.name); }
class Nul extends null { constructor() { return Object.create(Nul.prototype); } }
console.log(Object.getPrototypeOf(Nul.prototype) === null);
function OldStyle(v) { this.v = v; }
OldStyle.prototype.get = function () { return this.v; };
class Modern extends OldStyle { get() { return super.get() * 2; } }
console.log(new Modern(21).get());
try { class X extends 5 {} } catch (e) { console.log(e.name); }
const mixin = Base => class extends Base { mixed() { return "mixed"; } };
console.log(new (mixin(Animal))("m").mixed());
