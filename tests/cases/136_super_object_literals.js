// §13.3.7 super property references in object literal methods ([[HomeObject]]).
const base = { greet() { return "base:" + this.name; } };
const derived = { __proto__: base, name: "derived", greet() { return "derived>" + super.greet(); } };
console.log(derived.greet());
const borrowed = { name: "borrower", greet: derived.greet };
console.log(borrowed.greet());
const obj = { __proto__: { v: 1 }, get v() { return super.v + 100; } };
console.log(obj.v);
class A { static who() { return "A"; } }
class B extends A { static who() { return super.who() + "B"; } }
console.log(B.who());
const setter = { __proto__: { set p(v) { this._p = "proto set " + v; } }, set p(v) { super.p = v + "!"; } };
setter.p = "x";
console.log(setter._p);
