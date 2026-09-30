// §20.2.3 Function.prototype.call/apply/bind and this binding rules.
function who(greeting, punct) { return greeting + " " + this.name + punct; }
const p = { name: "Ada" };
console.log(who.call(p, "Hi", "!"), who.apply(p, ["Yo", "?"]));
const bound = who.bind(p, "Hey");
console.log(bound("."), bound.length, bound.name);
const rebound = bound.bind({ name: "Other" });
console.log(rebound("~"));
const o = { name: "o", get() { return this.name; } };
const loose = o.get;
console.log(o.get(), (o.get)(), (0, o.get).call({ name: "c" }));
function Pt(x) { this.x = x; }
const BP = Pt.bind(null, 7);
const inst = new BP();
console.log(inst.x, inst instanceof Pt, inst instanceof BP);
function prim() { "use strict"; return typeof this; }
console.log(prim.call(5), prim.call(null), prim.call(undefined));
function primS() { return typeof this; }
console.log(primS.call(5), primS.call("s"));
console.log(Math.max.apply(null, [1, 5, 2]), Array.prototype.slice.call("abc").join("|"));
