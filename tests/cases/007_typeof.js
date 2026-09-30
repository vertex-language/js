// §13.5.3 typeof operator.
console.log(typeof 1, typeof "s", typeof true, typeof undefined, typeof null);
console.log(typeof {}, typeof [], typeof function () {}, typeof class {}, typeof (() => 1));
console.log(typeof Symbol(), typeof 10n, typeof NaN, typeof new Number(1));
console.log(typeof notDeclaredAnywhere);
console.log(typeof typeof 1, typeof Math, typeof JSON, typeof Date, typeof new Date(0));
console.log(typeof async function () {}, typeof function* () {});
