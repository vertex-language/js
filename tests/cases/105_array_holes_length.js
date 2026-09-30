// Array exotic objects: length semantics, holes vs undefined, index keys.
const a = [1, 2, 3];
a.length = 1;
console.log(a.join(), a[2]);
a[5] = "f";
console.log(a.length, 3 in a, a.join("|"));
const h = [, "b"];
console.log(0 in h, h.hasOwnProperty(1), Object.keys(h).join());
try { a.length = -1; } catch (e) { console.log(e.name); }
const b = [];
b["2"] = 1; b["02"] = 2; b[-1] = 3; b[1.5] = 4;
console.log(b.length, Object.keys(b).join());
const fl = Object.defineProperty([1, 2, 3], "length", { writable: false });
try { "use strict"; fl.push(4); } catch (e) { console.log(e.name); }
console.log(fl.length, [].length = 0, [1, 2, 3].length = 2);
const big = [];
big[4294967294] = "max";
console.log(big.length);
big[4294967295] = "not index";
console.log(big.length);
