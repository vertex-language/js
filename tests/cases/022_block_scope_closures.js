// §14.2 blocks and §14.7.4.2 per-iteration bindings for let in loops.
const fns = [];
for (let i = 0; i < 3; i++) fns.push(() => i);
console.log(fns.map(f => f()).join(","));
const vfns = [];
for (var j = 0; j < 3; j++) vfns.push(() => j);
console.log(vfns.map(f => f()).join(","));
const ofns = [];
for (const k of ["a", "b"]) ofns.push(() => k);
console.log(ofns.map(f => f()).join(","));
let shadow = "outer";
{ let shadow = "inner"; console.log(shadow); }
console.log(shadow);
const infns = [];
for (const key in { p: 1, q: 2 }) infns.push(() => key);
console.log(infns.map(f => f()).join(","));
const mut = [];
for (let i = 0; i < 3; i++) { mut.push(() => i); i++; }
console.log(mut.map(f => f()).join(","));
