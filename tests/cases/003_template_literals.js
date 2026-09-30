// §13.2.8 Template literals.
const a = 5, b = 10;
console.log(`sum ${a + b} and ${a * b}`);
console.log(`multi
line`.split("\n").length);
console.log(`nested ${`inner ${a}`}`);
console.log(`${null} ${undefined} ${true} ${[1, 2]} ${{}}`);
console.log(`\${escaped}`, `back\`tick`);
const obj = { toString() { return "TS"; }, valueOf() { return "VO"; } };
console.log(`${obj}`, "" + obj);
console.log(`a${1}b${2}c`.length);
