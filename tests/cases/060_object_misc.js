// Object.hasOwn, Object.groupBy, Map.groupBy, hasOwnProperty, propertyIsEnumerable, toString tags.
const o = { own: 1 };
console.log(Object.hasOwn(o, "own"), Object.hasOwn(o, "toString"), o.hasOwnProperty("own"));
console.log(o.propertyIsEnumerable("own"), [].propertyIsEnumerable("length"));
const people = [{ n: "a", age: 20 }, { n: "b", age: 31 }, { n: "c", age: 25 }];
const g = Object.groupBy(people, p => p.age >= 25 ? "senior" : "junior");
console.log(Object.getPrototypeOf(g), Object.keys(g).join(), g.senior.map(p => p.n).join());
const mg = Map.groupBy([1, 2, 3, 4], n => n % 2 ? "odd" : "even");
console.log(mg.get("odd").join(), mg.get("even").join());
const ts = x => Object.prototype.toString.call(x);
console.log(ts(null), ts(undefined), ts([]), ts(1), ts(""), ts(true), ts(() => {}), ts(new Date(0)), ts(/x/), ts(new Error()));
console.log(ts(Math), ts(JSON), ts(Symbol()), ts(1n), ts(new Map()), ts(Promise.resolve()), ts(function* () {}()));
console.log(String({}), String(Object.create(null, { toString: { value: () => "custom" } })));
console.log(({}).valueOf() !== undefined, Object(1) instanceof Number, typeof Object("s"), Object(null) instanceof Object);
