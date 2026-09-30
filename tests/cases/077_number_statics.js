// §21.1.2 Number constructor properties and conversion.
console.log(Number.isInteger(5), Number.isInteger(5.0), Number.isInteger(5.1), Number.isInteger("5"));
console.log(Number.isSafeInteger(2 ** 53 - 1), Number.isSafeInteger(2 ** 53), Number.isFinite("1"), isFinite("1"));
console.log(Number.isNaN("x"), isNaN("x"), Number.isNaN(NaN));
console.log(Number.MAX_SAFE_INTEGER, Number.MIN_SAFE_INTEGER, Number.EPSILON > 0, Number.EPSILON === 2 ** -52);
console.log(Number.MAX_VALUE, Number.MIN_VALUE, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY);
console.log(Number("  42  "), Number(""), Number("0b101"), Number("0o17"), Number("-0x10"), Number("1_000"), Number(null), Number(undefined));
console.log(Number("Infinity"), Number("-Infinity"), Number("infinity"), Number([]), Number(["7"]), Number(false), Number(12n));
console.log(Number.parseFloat === parseFloat, Number.parseInt === parseInt);
