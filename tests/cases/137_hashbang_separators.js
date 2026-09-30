#!/usr/bin/env node
// ES2023 hashbang comments; numeric separators and literal forms.
console.log(1_000, 1_0.5_0);
console.log(0b1010_1010, 0o7_7, 0xDE_AD, 1_0e1_0, String(1_000n));
for (const bad of ["1__0", "1_", "_1 === _1", "0_1", "1._5"]) {
  try { eval(bad); console.log("parsed", bad); } catch (e) { console.log(e.name, bad); }
}
