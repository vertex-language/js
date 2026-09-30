// §13.10 Relational operators, string comparison, NaN.
console.log(1 < 2, 2 < 1, 2 <= 2, 3 >= 4, "a" < "b", "B" < "a", "10" < "9", 10 < "9");
console.log("abc" < "abd", "ab" < "abc", NaN < 1, NaN >= NaN, undefined < 1, null < 1, null >= 0);
console.log([2] > 1, "x" > 1, "x" < 1, 1n < 2, 2n > 1.5, "10" > 9n);
const o = { valueOf() { return 5; } };
console.log(o > 4, o < 6, o <= 5);
