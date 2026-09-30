// §13.6 Exponentiation operator.
console.log(2 ** 10, 2 ** -1, (-2) ** 3, 2 ** 3 ** 2, 4 ** 0.5);
let x = 3;
x **= 2;
console.log(x, NaN ** 0, 1 ** Infinity, 0 ** -1, (-8) ** (1 / 3));
console.log(2n ** 64n === 18446744073709551616n);
