// ES2023 change-array-by-copy: toSorted/toReversed/toSpliced/with.
const a = [3, 1, 2];
const s = a.toSorted(), r = a.toReversed(), sp = a.toSpliced(1, 1, "x", "y"), w = a.with(0, 9);
console.log(a.join(), s.join(), r.join(), sp.join(), w.join(), a.with(-1, 0).join());
try { a.with(5, 1); } catch (e) { console.log(e.name); }
console.log([1, , 3].toSorted().join("|"), 1 in [1, , 3].toReversed(), a.toSorted((x, y) => y - x).join());
