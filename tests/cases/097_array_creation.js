// §23.1 Array constructor, Array.of, Array.from, isArray.
console.log(Array(3).length, Array(3, 4).join(), Array("3").length, new Array().length, [,].length, [1, , 3].length);
try { Array(1.5); } catch (e) { console.log(e.name); }
console.log(Array.of(3).join(), Array.of(1, 2).length, Array.of().length);
console.log(Array.from("abc").join(), Array.from({ length: 3 }, (_, i) => i * i).join(), Array.from(new Set([1, 1, 2])).join());
console.log(Array.from({ length: 2, 0: "x", 1: "y" }).join(), Array.from([1, 2], function (x) { return x * this.k; }, { k: 10 }).join());
console.log(Array.isArray([]), Array.isArray({ length: 0 }), Array.isArray(Array.prototype), Array.isArray(new Proxy([], {})));
console.log(JSON.stringify(Array.from(new Map([[1, 2]]))), Array.from(5).length);
