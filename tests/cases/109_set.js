// §24.2 Set: uniqueness, order, and iteration.
const s = new Set([3, 1, 3, 2, 1, NaN, NaN, "1"]);
console.log(s.size, [...s].map(String).join());
console.log(s.add(4) === s, s.has(4), s.has("3"), s.delete(3), s.delete(3), s.size);
const seen = [];
s.forEach((v, k) => seen.push(v === k));
console.log(seen.every(Boolean), [...s.entries()][0].join(":"), s.keys === s.values);
const dedupe = [...new Set("mississippi")].join("");
console.log(dedupe);
const live = new Set([1]);
for (const v of live) { if (v < 4) live.add(v + 1); }
console.log([...live].join());
