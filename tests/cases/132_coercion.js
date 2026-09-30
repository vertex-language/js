// §7.1 ToPrimitive order (valueOf vs toString), hints, and failures.
const log = [];
const obj = {
  valueOf() { log.push("valueOf"); return 10; },
  toString() { log.push("toString"); return "str"; },
};
console.log(obj + 1, `${obj}`, obj * 2, String(obj), obj + "", [obj] + "");
console.log(log.join(","));
const onlyToString = { toString() { return "7"; } };
console.log(onlyToString * 2, onlyToString + 1);
const bad = { valueOf() { return {}; }, toString() { return {}; } };
try { bad + 1; } catch (e) { console.log(e.name); }
const objValueOf = { valueOf() { return {}; }, toString() { return "fallback"; } };
console.log(objValueOf + 1);
console.log([] + {}, [1, 2] + [3], ({}).toString(), [[]] == 0, [[1]] == 1, new Date(0) + 0 === new Date(0).toString() + "0");
console.log(1 + true, "1" + true, 1 + undefined, "1" + undefined, true + true, [] - 1, [5] * [2]);
