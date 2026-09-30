// §21.1.3 Number.prototype.toFixed/toPrecision/toExponential/toString(radix).
console.log((3.14159).toFixed(2), (0.5).toFixed(0), (1.5).toFixed(0), (2.5).toFixed(0), (1.005).toFixed(2), (1e21).toFixed(2));
console.log((123.456).toPrecision(4), (0.00012345).toPrecision(2), (123456).toPrecision(2), (5).toPrecision(3));
console.log((12345).toExponential(2), (0).toExponential(), (0.00015).toExponential(1), (1).toExponential(3));
console.log((255).toString(16), (255).toString(2), (-255).toString(36), (0.5).toString(2), (3.75).toString(8));
console.log((10).toString(), (1e21).toString(), (123.0).toString(), (-0).toString());
try { (1).toString(1); } catch (e) { console.log(e.name); }
console.log(Number.prototype.toFixed.call(new Number(7), 1), (42).valueOf(), typeof new Number(42).valueOf());
