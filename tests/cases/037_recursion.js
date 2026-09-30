// Recursion, mutual recursion, and deep (but reasonable) call depth.
function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
console.log(fib(20));
const isEven = n => n === 0 ? true : isOdd(n - 1);
const isOdd = n => n === 0 ? false : isEven(n - 1);
console.log(isEven(100), isOdd(7));
function depth(n) { return n === 0 ? 0 : 1 + depth(n - 1); }
console.log(depth(5000));
function hanoi(n, from, to, via, moves) { if (n === 0) return moves; hanoi(n - 1, from, via, to, moves); moves.push(from + to); return hanoi(n - 1, via, to, from, moves); }
console.log(hanoi(4, "A", "C", "B", []).length);
function flatten(a) { return a.reduce((acc, x) => Array.isArray(x) ? acc.concat(flatten(x)) : acc.concat(x), []); }
console.log(flatten([1, [2, [3, [4, [5]]]]]).join(""));
function runaway() { return runaway(); }
try { runaway(); } catch (e) { console.log(e instanceof RangeError); }
