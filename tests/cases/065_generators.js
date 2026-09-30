// §27.5 generator functions.
function* count(n) { for (let i = 0; i < n; i++) yield i; return "end"; }
const g = count(2);
console.log(JSON.stringify([g.next(), g.next(), g.next(), g.next()]));
function* echo() { let received = []; while (received.length < 3) received.push(yield received.length); return received.join(); }
const e = echo();
e.next("ignored");
e.next("a"); e.next("b");
console.log(e.next("c").value);
function* fibs() { let [a, b] = [0, 1]; for (;;) { yield a; [a, b] = [b, a + b]; } }
const out = [];
for (const f of fibs()) { if (f > 50) break; out.push(f); }
console.log(out.join(","));
console.log(typeof count, Object.prototype.toString.call(count(1)), count(1)[Symbol.iterator]() instanceof count);
const lazy = { *[Symbol.iterator]() { yield* [1, 2]; yield 3; } };
console.log([...lazy].join());
try { new count(); } catch (err) { console.log(err.name); }
const gen = count(5);
console.log([...gen].length, [...gen].length);
