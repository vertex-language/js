// §14.7 for, while, do-while.
let s = 0;
for (let i = 1; i <= 10; i++) s += i;
console.log(s);
let n = 0;
while (n < 5) n += 2;
console.log(n);
let d = 10;
do { d++; } while (d < 5);
console.log(d);
let k = 0;
for (;;) { if (++k === 4) break; }
console.log(k);
const out = [];
for (let i = 0, j = 5; i < j; i += 2, j--) out.push(i + ":" + j);
console.log(out.join(" "));
let cnt = 0;
for (let i = 0; i < 10; i++) { if (i % 3) continue; cnt++; }
console.log(cnt);
