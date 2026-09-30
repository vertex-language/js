// §21.3 Math: sign, cbrt, hypot, clz32, fround, imul, logs, trig.
console.log(Math.sign(-3), Math.sign(0), Math.sign(7), Math.sign("x"), Math.cbrt(27), Math.cbrt(-8), Math.hypot(3, 4), Math.hypot(), Math.hypot(3, 4, 12));
console.log(Math.clz32(1), Math.clz32(0), Math.clz32(-1), Math.fround(5.5), Math.fround(5.05), Math.imul(3, 4), Math.imul(0xffffffff, 5));
console.log(Math.log(Math.E), Math.log2(8), Math.log10(1000), Math.log1p(0), Math.expm1(0), Math.exp(0), Math.log(-1), Math.log(0));
console.log(Math.sin(0), Math.cos(0), Math.tan(0), Math.atan2(1, 1) === Math.PI / 4, Math.asin(1) === Math.PI / 2, Math.acos(1));
console.log(Math.sinh(0), Math.cosh(0), Math.tanh(Infinity), Math.asinh(0), Math.acosh(1), Math.atanh(0));
console.log(Math.abs(Math.sin(Math.PI)) < 1e-15, Math.round(Math.cos(Math.PI)), Math.atan(Infinity) === Math.PI / 2);
console.log(Object.prototype.toString.call(Math), typeof Math.max, Math.max.length, Math.hypot.length);
