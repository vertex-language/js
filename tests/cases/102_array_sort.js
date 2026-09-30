// §23.1.3.30 sort: default string order, comparators, stability, undefined/holes.
console.log([10, 9, 1, 100, 25].sort().join(), [10, 9, 1, 100, 25].sort((a, b) => a - b).join());
console.log(["b", "a", "C", "B"].sort().join(), [3, undefined, 1, , 2].sort().join("|"), [3, undefined, 1, , 2].sort().length);
const people = [{ n: "a", g: 2 }, { n: "b", g: 1 }, { n: "c", g: 2 }, { n: "d", g: 1 }, { n: "e", g: 2 }];
console.log(people.sort((x, y) => x.g - y.g).map(p => p.n).join(""));
const big = Array.from({ length: 100 }, (_, i) => ({ k: i % 3, i }));
big.sort((a, b) => a.k - b.k);
console.log(big.every((x, i, arr) => i === 0 || arr[i - 1].k < x.k || arr[i - 1].i < x.i));
const arr = [3, 1, 2];
console.log(arr.sort() === arr, ["é", "e", "z", "a"].sort().join(""), [true, false].sort().join());
try { [1, 2].sort("not fn"); } catch (e) { console.log(e.name); }
