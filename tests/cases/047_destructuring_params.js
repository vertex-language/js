// Destructuring in parameters, for-of heads, and catch clauses.
function area({ w = 1, h = 1 } = {}) { return w * h; }
console.log(area(), area({ w: 3 }), area({ w: 2, h: 5 }));
function head([first, ...tail]) { return first + "|" + tail.length; }
console.log(head([9, 8, 7]));
const pts = [{ x: 1, y: 2 }, { x: 3, y: 4 }];
let sum = 0;
for (const { x, y } of pts) sum += x * y;
console.log(sum);
for (const [i, v] of ["a", "b"].entries()) console.log(i, v);
const m = new Map([["k1", { v: 1 }], ["k2", { v: 2 }]]);
for (const [k, { v }] of m) console.log(k, v);
const fn = ({ a, b: [c, d] }) => a + c + d;
console.log(fn({ a: 1, b: [2, 3] }));
console.log(((...[x, y]) => x * y)(6, 7));
