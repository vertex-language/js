// map/filter/reduce/reduceRight/forEach with index, array and thisArg.
const a = [1, 2, 3, 4];
console.log(a.map((x, i, arr) => x * i + arr.length).join(), a.filter(x => x % 2).join());
console.log(a.reduce((s, x) => s + x), a.reduce((s, x) => s + x, 10), a.reduceRight((s, x) => s + x, ""));
try { [].reduce((a, b) => a); } catch (e) { console.log(e.name); }
console.log([5].reduce((a, b) => a + b), [].reduce((a, b) => a + b, "init"));
const seen = [];
[1, , 3].forEach((x, i) => seen.push(i));
console.log(seen.join(), [1, , 3].map(x => x * 2).length, 1 in [1, , 3].map(x => x));
console.log([1, 2].map(function () { return this.v; }, { v: "ctx" }).join());
const grow = [1, 2];
grow.forEach(x => { if (grow.length < 5) grow.push(x); });
console.log(grow.join());
