// §15.1 rest parameters, §13.3.8 spread in calls and array literals.
function r(first, ...rest) { return first + ":" + rest.length + ":" + Array.isArray(rest); }
console.log(r(1), r(1, 2, 3));
console.log(Math.max(...[3, 9, 2]), Math.min(...[3, 9, 2], -1));
const a = [1, 2], b = [3];
console.log([...a, ...b, 4].join(","), [..."héllo"].length, [...new Set([1, 1, 2])].join(","));
function cnt() { return arguments.length; }
console.log(cnt(...[], ...[1, 2], 3));
const it = { *[Symbol.iterator]() { yield "x"; yield "y"; } };
console.log([...it].join(""));
try { [...{}]; } catch (e) { console.log(e.name); }
console.log(r.length);
