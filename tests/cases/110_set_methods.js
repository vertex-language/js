// ES2025 Set methods: union, intersection, difference, symmetricDifference, subset/superset/disjoint.
const a = new Set([1, 2, 3]), b = new Set([3, 4]);
console.log([...a.union(b)].join(), [...a.intersection(b)].join(), [...a.difference(b)].join(), [...a.symmetricDifference(b)].join());
console.log(new Set([1]).isSubsetOf(a), a.isSupersetOf(new Set([2, 3])), a.isDisjointFrom(new Set([9])), a.isDisjointFrom(b));
const setLike = { size: 2, has: x => x === 1 || x === 5, keys: () => [1, 5][Symbol.iterator]() };
console.log([...a.union(setLike)].join(), [...a.intersection(setLike)].join());
try { a.union([1]); } catch (e) { console.log(e.name); }
console.log([...a.union(new Map([[7, "v"]]))].join());
