// §14.13 labelled statements with break/continue.
const out = [];
outer: for (let i = 0; i < 3; i++) {
  for (let j = 0; j < 3; j++) {
    if (j === 1) continue outer;
    if (i === 2) break outer;
    out.push(`${i}${j}`);
  }
}
console.log(out.join(","));
block: {
  console.log("in block");
  break block;
  console.log("never");
}
let w = 0;
loop: while (true) { do { w++; if (w > 3) break loop; } while (true); }
console.log(w);
