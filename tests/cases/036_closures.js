// §9.1 environments: closures capture bindings, not values.
function counter() {
  let n = 0;
  return { inc: () => ++n, dec: () => --n, get: () => n };
}
const c1 = counter(), c2 = counter();
c1.inc(); c1.inc(); c2.dec();
console.log(c1.get(), c2.get());
function adder(x) { return y => z => x + y + z; }
console.log(adder(1)(2)(3));
let later = "before";
const read = () => later;
later = "after";
console.log(read());
const memo = (fn => { const cache = new Map(); return n => cache.has(n) ? cache.get(n) : (cache.set(n, fn(n)), cache.get(n)); })(n => n * n);
console.log(memo(9), memo(9));
const mod = (function () { let priv = 0; return { bump() { return ++priv; } }; })();
mod.bump();
console.log(mod.bump(), typeof priv);
