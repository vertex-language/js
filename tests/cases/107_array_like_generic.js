// Array methods are generic over array-likes; strings are array-like.
const al = { 0: "a", 1: "b", 2: "c", length: 3 };
console.log(Array.prototype.map.call(al, s => s.toUpperCase()).join(), Array.prototype.join.call(al, "-"));
console.log(Array.prototype.filter.call("hello", c => c !== "l").join(""), Array.prototype.reverse.call({ 0: 1, 1: 2, length: 2 })[0]);
console.log(Array.prototype.indexOf.call("abc", "c"), [].slice.call({ length: 2, 0: "x" }).length);
function f() { return Array.prototype.slice.call(arguments, 1).join(); }
console.log(f(1, 2, 3));
console.log(Array.prototype.includes.call({ length: 1, 0: NaN }, NaN));
