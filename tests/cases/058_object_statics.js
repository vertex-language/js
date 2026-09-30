// §20.1.2 Object.keys/values/entries/fromEntries/assign/getOwnPropertyNames/Symbols.
const o = { b: 2, a: 1, [Symbol("s")]: 3 };
console.log(Object.keys(o).join(), Object.values(o).join(), JSON.stringify(Object.entries(o)));
console.log(JSON.stringify(Object.fromEntries([["x", 1], ["y", 2]])));
console.log(JSON.stringify(Object.fromEntries(new Map([["m", true]]))));
const t = Object.assign({ a: 0 }, { a: 1, b: 1 }, null, { c: 1 }, "hi");
console.log(JSON.stringify(t));
console.log(Object.getOwnPropertyNames([1, 2]).join(), Object.getOwnPropertySymbols(o).length);
console.log(Object.keys("abc").join(), Object.entries([7, 8]).join("|"));
const log = [];
Object.assign({ set x(v) { log.push("setter " + v); } }, { x: 1 });
console.log(log.join());
console.log(Object.getOwnPropertyNames(Object.prototype).includes("hasOwnProperty"));
