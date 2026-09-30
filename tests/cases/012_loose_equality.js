// §7.2.14 IsLooselyEqual.
console.log(1 == "1", 0 == "", 0 == "0", "" == "0", null == undefined, null == 0, undefined == 0);
console.log(NaN == NaN, [] == false, [] == ![], [0] == false, [1, 2] == "1,2", {} == "[object Object]");
console.log(true == 1, true == "1", true == "true", 1n == 1, 1n == "1", 2n == true);
const o = { valueOf() { return 42; } };
console.log(o == 42, o == "42", o != 43);
const s = Symbol("s");
console.log(s == s, Object(s) == s);
