// §12.9.3 Numeric literals: decimal, exponent, hex, octal, binary, separators.
console.log(42, 3.14, .5, 5., 1e3, 2E-2);
console.log(0xff, 0XA0, 0o17, 0O7, 0b1010, 0B11);
console.log(1_000_000);
console.log(0.1 + 0.2, 1 / 3, 2 ** 53, 2 ** 53 + 1);
console.log(1e21, 1e-7, 123456789012345680000, 5e-324, 1.7976931348623157e308);
console.log(Infinity, -Infinity, NaN, 1 / 0, -1 / 0);
console.log(Object.is(-0, 0), Object.is(1 / -Infinity, -0));
