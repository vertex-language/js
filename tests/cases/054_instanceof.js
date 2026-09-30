// §13.10.2 instanceof and Symbol.hasInstance.
function F() {}
const f = new F();
console.log(f instanceof F, f instanceof Object, [] instanceof Array, [] instanceof Object);
console.log(Object.create(null) instanceof Object, 5 instanceof Number, new Number(5) instanceof Number);
class Even { static [Symbol.hasInstance](n) { return n % 2 === 0; } }
console.log(2 instanceof Even, 3 instanceof Even);
F.prototype = {};
console.log(f instanceof F);
try { ({}) instanceof {}; } catch (e) { console.log(e.name); }
const bound = F.bind(null);
console.log(new F() instanceof bound);
console.log(Function instanceof Function, Object instanceof Function, Function instanceof Object);
