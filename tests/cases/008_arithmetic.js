// §13.7-13.8 Multiplicative & additive operators with coercion.
console.log(7 + 3, 7 - 3, 7 * 3, 7 / 2, 7 % 3, -7 % 3, 7 % -3, 5.5 % 2);
console.log("3" + 4, 3 + "4", "3" - 1, "3" * "4", "12" / "4", "a" * 1);
console.log(true + 1, null + 1, undefined + 1, [] + [], [1] + [2], {} + "");
console.log(+"", +" 12 ", +"0x10", +"1e3", +"12px", +[], +[5], +[1, 2], +null, +true);
console.log(-"5", - -"5", 1 - -1);
console.log(0.1 * 3, 9007199254740993, 1 / 3 * 3);
console.log(Infinity - Infinity, Infinity * 0, 5 % 0, Infinity % 2, 2 % Infinity);
console.log(Object.is(-5 % 5, -0), Object.is(0 * -1, -0));
