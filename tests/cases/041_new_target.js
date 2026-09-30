// §13.3.12 new.target.
function F() { return new.target === F ? "new" : String(new.target); }
console.log(new F() instanceof F, F());
function G() { if (!new.target) return "must use new"; this.ok = true; }
console.log(G(), new G().ok);
class A { constructor() { this.nt = new.target.name; } }
class B extends A {}
console.log(new A().nt, new B().nt);
function H() { return (() => new.target)(); }
console.log(new H() instanceof H ? "obj" : "fn", H() === undefined);
console.log(Reflect.construct(A, [], B).nt);
