// JSON.stringify replacer (function and array), toJSON, cycles.
console.log(JSON.stringify({ a: 1, b: 2, c: { a: 3, d: 4 } }, ["a", "c"]));
console.log(JSON.stringify({ a: 1, b: "x", c: [1, 2] }, (k, v) => typeof v === "number" ? v * 10 : v));
const keys = [];
JSON.stringify({ x: { y: 1 } }, function (k, v) { keys.push(k === "" ? "(root)" : k); return v; });
console.log(keys.join());
console.log(JSON.stringify({ toJSON(key) { return "custom:" + key; } }), JSON.stringify({ nested: { toJSON: k => k } }));
const cyc = { name: "c" };
cyc.self = cyc;
try { JSON.stringify(cyc); } catch (e) { console.log(e.name); }
console.log(JSON.stringify({ a: 1 }, (k, v) => k === "a" ? undefined : v), JSON.stringify([1, 2], (k, v) => k === "0" ? undefined : v));
console.log(JSON.stringify({ 2: "b", 1: "a", x: "x" }), JSON.stringify({ a: 1 }, [1, "a"]));
