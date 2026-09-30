// §7.2.15 IsStrictlyEqual, SameValue, SameValueZero.
console.log(1 === 1, 1 === "1", NaN === NaN, 0 === -0, null === null, undefined === null);
const a = {}, b = {};
console.log(a === a, a === b, [] === [], "ab" === "a" + "b");
console.log(Object.is(NaN, NaN), Object.is(0, -0), Object.is("x", "x"));
console.log([NaN].includes(NaN), [NaN].indexOf(NaN), new Set([0, -0, NaN, NaN]).size);
console.log(1 !== 2, "a" !== "a");
