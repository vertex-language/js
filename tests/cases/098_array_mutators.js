// push/pop/shift/unshift/splice/reverse/fill/copyWithin.
const a = [1, 2, 3];
console.log(a.push(4, 5), a.pop(), a.shift(), a.unshift(0, 1), a.join());
const s = [1, 2, 3, 4, 5];
console.log(s.splice(1, 2).join(), s.join());
console.log(s.splice(1, 0, "x", "y").length, s.join());
console.log(s.splice(-2).join(), s.join(), s.splice(1, 1, "z").join(), s.join());
console.log([].pop(), [].shift(), [1, 2, 3].reverse().join());
console.log(new Array(4).fill(0).join(), [1, 2, 3, 4].fill(9, 1, -1).join(), [1, 2, 3, 4, 5].copyWithin(0, 3).join(), [1, 2, 3, 4, 5].copyWithin(1, 0, 2).join());
const arrLike = { length: 1, 0: "a" };
Array.prototype.push.call(arrLike, "b");
console.log(arrLike.length, arrLike[1]);
