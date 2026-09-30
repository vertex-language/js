// find/findIndex/findLast/findLastIndex/some/every.
const a = [5, 12, 8, 130, 44];
console.log(a.find(x => x > 10), a.findIndex(x => x > 10), a.findLast(x => x > 10), a.findLastIndex(x => x > 10));
console.log(a.find(x => x > 1000), a.findIndex(x => x > 1000), a.findLastIndex(() => false));
console.log(a.some(x => x > 100), a.every(x => x > 1), [].some(() => true), [].every(() => false));
let visits = 0;
[1, , 3].find(() => { visits++; return false; });
console.log(visits);
