// §14.3.1 const bindings are immutable; the objects they hold are not.
const c = 1;
try { c = 2; } catch (e) { console.log(e.name); }
const o = { n: 1 };
o.n = 2;
console.log(o.n);
try { for (const i = 0; i < 2; i++) {} } catch (e) { console.log("loop", e.name); }
const f = function named() {
  try { named = 5; } catch (e) { return "threw"; }
  return typeof named;
};
console.log(f());
const g = function named() { "use strict"; try { named = 5; } catch (e) { return e.name; } };
console.log(g());
