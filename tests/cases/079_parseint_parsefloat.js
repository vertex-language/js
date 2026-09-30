// §19.2.5 parseInt, §19.2.4 parseFloat.
console.log(parseInt("42px"), parseInt("  -17  "), parseInt("0x1F"), parseInt("1F", 16), parseInt("101", 2), parseInt("z", 36));
console.log(parseInt(""), parseInt("abc"), parseInt("08"), parseInt("0b11"), parseInt("12", 1), parseInt("12", 37), parseInt("12", 0));
console.log(parseInt(0.0000005), parseInt("1e3"), parseInt(null, 36), Object.is(parseInt("-0"), -0), parseInt("123456789012345678901234567890"));
console.log(parseFloat("3.14abc"), parseFloat(".5"), parseFloat("-.5e2"), parseFloat("Infinityx"), parseFloat("1e"), parseFloat("0x10"), parseFloat("  +1.2  "));
console.log(parseFloat("abc"), parseFloat("1.2.3"), parseFloat("-0") === 0);
console.log(["1", "2", "3"].map(parseInt).join(), ["1", "2", "3"].map(Number).join());
