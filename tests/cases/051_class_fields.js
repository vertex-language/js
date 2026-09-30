// §15.7 public instance fields: initialization order, this, computed names.
let log = [];
class Base { constructor() { log.push("base ctor"); } }
class C extends Base {
  a = (log.push("field a"), 1);
  b = this.a + 1;
  ["comp" + "uted"] = "yes";
  arrow = () => this.b;
  constructor() { log.push("before super"); super(); log.push("after super"); }
}
const c = new C();
console.log(log.join(" > "));
console.log(c.a, c.b, c.computed, c.arrow.call(null));
console.log(Object.keys(c).join(","));
class D { x; y = undefined; }
console.log("x" in new D(), Object.keys(new D()).join(","));
class E { static s = this.name; i = this.constructor.name; }
console.log(E.s, new E().i);
class Parent { field = "parent"; }
class Child extends Parent { field = "child"; }
console.log(new Child().field);
