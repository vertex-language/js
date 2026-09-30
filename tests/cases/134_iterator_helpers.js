// ES2025 Iterator helpers and Iterator.from.
function* nat() { let i = 0; while (true) yield i++; }
console.log(nat().map(x => x * 2).filter(x => x % 3 === 0).take(4).toArray().join());
console.log(nat().drop(5).take(2).toArray().join(), nat().take(3).reduce((a, b) => a + b, 0));
console.log(nat().take(5).some(x => x > 3), nat().take(5).every(x => x < 5), nat().find(x => x > 10));
console.log([...nat().take(2).flatMap(x => [x, "-"])].join(""));
const seen = [];
nat().take(3).forEach(x => seen.push(x));
console.log(seen.join());
const wrapped = Iterator.from({ next() { return { done: this.i > 2, value: this.i++ }; }, i: 0 });
console.log(wrapped.toArray().join(), typeof Iterator, [].values() instanceof Iterator);
try { nat().take(-1); } catch (e) { console.log(e.name); }
