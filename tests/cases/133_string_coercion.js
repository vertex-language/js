// §7.1.17 ToString of each type, String() vs template vs concatenation.
const vals = [0, -0, 1.5, 1e21, NaN, true, null, undefined, [], [1, [2, 3]], {}, function f() {}.name];
console.log(vals.map(v => String(v)).join("|"));
console.log(String(Symbol("sym")), String(12n), String([null]), String([undefined, 1]), String(new String("wrapped")));
try { `${Symbol()}`; } catch (e) { console.log(e.name); }
console.log(String(Object.create(null, { [Symbol.toPrimitive]: { value: () => "prim" } })));
try { String(Object.create(null)); } catch (e) { console.log(e.name); }
console.log(typeof String(1), typeof new String(1), new String("ab").length, new String("ab")[1], Object.keys(new String("ab")).join());
