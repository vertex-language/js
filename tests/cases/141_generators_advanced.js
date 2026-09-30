// Generator methods in classes/objects, infinite streams, destructuring from generators.
class Tree {
  constructor(v, ...kids) { this.v = v; this.kids = kids; }
  *[Symbol.iterator]() { yield this.v; for (const k of this.kids) yield* k; }
}
const tree = new Tree(1, new Tree(2, new Tree(3)), new Tree(4));
console.log([...tree].join());
const [first, , third, ...rest] = (function* () { yield* "abcdef"; })();
console.log(first, third, rest.join(""));
function* take(n, it) { for (const x of it) { if (n-- <= 0) return; yield x; } }
function* primes() { const found = []; for (let n = 2; ; n++) if (found.every(p => n % p)) { found.push(n); yield n; } }
console.log([...take(10, primes())].join());
const obj = { *gen() { yield this.k; }, k: "method gen" };
console.log(obj.gen().next().value);
function* argsGen() { yield arguments.length; yield* arguments; }
console.log([...argsGen("x", "y")].join());
