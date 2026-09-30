// §13.15 Logical assignment operators (&&=, ||=, ??=).
let a = 0, b = 1, c = null, d = "set";
a ||= 5; b &&= 7; c ??= "nn"; d ??= "no";
console.log(a, b, c, d);
let calls = 0;
const o = { get v() { calls++; return 1; }, set v(x) { calls += 100; } };
o.v ||= 2;
o.v &&= 3;
console.log(calls);
const cfg = {};
cfg.retries ??= 3;
cfg.retries ??= 9;
console.log(cfg.retries);
