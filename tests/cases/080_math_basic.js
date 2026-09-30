// §21.3 Math: rounding, min/max, abs, sqrt, pow, constants.
console.log(Math.round(2.5), Math.round(-2.5), Math.round(2.4), Math.round(-0.4) === 0, Math.round(0.49999999999999994));
console.log(Math.floor(-1.5), Math.ceil(-1.5), Math.floor(1.9), Math.ceil(1.1), Math.trunc(-4.7), Math.trunc(4.7));
console.log(Math.max(), Math.min(), Math.max(1, NaN), Math.max(1, "5"), Math.min(-0, 0) === 0, Object.is(Math.min(0, -0), -0));
console.log(Math.abs(-5), Math.abs("-2"), Math.abs(null), Math.abs([]), Math.abs({}), Math.sqrt(16), Math.sqrt(-1), Math.pow(2, 10), Math.pow(NaN, 0));
console.log(Math.PI, Math.E, Math.LN2, Math.LN10, Math.LOG2E, Math.LOG10E, Math.SQRT2, Math.SQRT1_2);
const r = Math.random();
console.log(r >= 0 && r < 1, typeof r);
