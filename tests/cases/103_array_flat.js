// flat/flatMap and holes.
console.log([1, [2, [3, [4]]]].flat().length, [1, [2, [3, [4]]]].flat(2).length, [1, [2, [3, [4]]]].flat(Infinity).join());
console.log([1, , 3, [4, , 6]].flat().join("|"), [[]].flat().length);
console.log([1, 2].flatMap(x => [x, x * 10]).join(), [1, 2].flatMap(x => [[x]]).length, ["a b", "c"].flatMap(s => s.split(" ")).join());
