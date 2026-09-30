// Well-known symbols: toPrimitive, toStringTag, isConcatSpreadable, species, unscopables.
const money = {
  [Symbol.toPrimitive](hint) { return hint === "number" ? 42 : hint === "string" ? "$42" : "default"; },
};
console.log(+money, `${money}`, money + "", money * 2);
class Tagged { get [Symbol.toStringTag]() { return "MyTag"; } }
console.log(Object.prototype.toString.call(new Tagged()), String(new Tagged()));
const spreadable = { length: 2, 0: "a", 1: "b", [Symbol.isConcatSpreadable]: true };
console.log([1].concat(spreadable).join());
const arr = [1, 2];
arr[Symbol.isConcatSpreadable] = false;
console.log([0].concat(arr).length);
class PlainArr extends Array { static get [Symbol.species]() { return Array; } }
const pa = PlainArr.from([1, 2, 3]).filter(x => x > 1);
console.log(pa instanceof PlainArr, pa instanceof Array);
console.log(Object.keys(Array.prototype[Symbol.unscopables]).includes("flat"));
