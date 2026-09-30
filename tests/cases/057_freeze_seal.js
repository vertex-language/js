// §20.1.2 Object.freeze/seal/preventExtensions and their predicates.
const f = Object.freeze({ a: 1, nested: { b: 2 } });
f.a = 9; f.c = 3; delete f.a; f.nested.b = 20;
console.log(f.a, f.c, f.nested.b, Object.isFrozen(f), Object.isSealed(f), Object.isExtensible(f));
const s = Object.seal({ a: 1 });
s.a = 2; s.b = 3; delete s.a;
console.log(s.a, s.b, Object.isSealed(s), Object.isFrozen(s));
const p = Object.preventExtensions({ a: 1 });
p.b = 1; delete p.a;
console.log(p.a, p.b, Object.isExtensible(p));
console.log(Object.isFrozen(1), Object.isFrozen({}), Object.isFrozen(Object.preventExtensions({})));
const arr = Object.freeze([1, 2]);
try { arr.push(3); } catch (e) { console.log(e.name); }
console.log(arr.length, Object.freeze(5));
