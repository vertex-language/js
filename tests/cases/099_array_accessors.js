// slice/concat/join/indexOf/lastIndexOf/includes/at/toString.
const a = [1, 2, 3, 4, 5];
console.log(a.slice(1, 3).join(), a.slice(-2).join(), a.slice().length, a.slice(3, 1).length);
console.log(a.concat([6, [7]], 8).length, [].concat(1, [2], [[3]]).length);
console.log(a.indexOf(3), a.indexOf(3, 3), a.lastIndexOf(1), a.indexOf("3"), [NaN].indexOf(NaN), [NaN].includes(NaN), [1, , 3].includes(undefined), [1, , 3].indexOf(undefined));
console.log(a.at(-1), a.at(10), String([1, [2, [3]]]), [null, undefined].toString(), [1, 2].toString === Array.prototype.toString);
console.log([0].includes(-0), [1, 2, 3].includes(2, -1), [1, 2, 3].includes(3, -1));
