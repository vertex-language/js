// §13.4 Update expressions and ToNumeric.
let i = 5;
console.log(i++, i, ++i, i, i--, i, --i, i);
let s = "5";
s++;
console.log(s, typeof s);
let n = null; n++;
let u; u++;
console.log(n, u);
let big = 10n; big++;
console.log(String(big), typeof big);
const o = { v: 1 };
o.v++; ++o["v"];
console.log(o.v);
