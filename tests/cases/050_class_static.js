// §15.7 static methods, static fields and static initialization blocks.
class Registry {
  static count = 0;
  static items = [];
  static #secret = "hidden";
  static {
    this.items.push("init");
    Registry.ready = true;
  }
  static add(x) { this.items.push(x); return ++this.count; }
  static reveal() { return Registry.#secret; }
}
Registry.add("a");
console.log(Registry.count, Registry.items.join(","), Registry.ready, Registry.reveal());
class Sub extends Registry {}
console.log(Sub.count, Sub.add === Registry.add, Object.hasOwn(Sub, "count"));
Sub.add("b");
console.log(Sub.count, Registry.count);
try { Sub.reveal.call(Sub); } catch (e) { console.log(e.name); }
const order = [];
class Order { static a = order.push("a"); static { order.push("block"); } static b = order.push("b"); }
console.log(order.join(","));
