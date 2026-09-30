// Sloppy mode behaviours: implicit globals, silent failures, this coercion, Annex B function-in-block.
function mk() { implicit = "global"; }
mk();
console.log(globalThis.implicit, delete globalThis.implicit);
const frozen = Object.freeze({ a: 1 });
frozen.a = 2; frozen.b = 3;
console.log(frozen.a, frozen.b);
console.log(delete Object.prototype, delete [].length, delete 5, delete undeclaredName);
function thisType() { return typeof this; }
console.log(thisType.call(1), thisType.call(null) === "object" && thisType.call(null) !== undefined);
{
  function blockFn() { return "annex b"; }
}
console.log(typeof blockFn, blockFn());
if (true) function ifFn() { return "if-declared"; }
console.log(ifFn());
var dup = 1; var dup = 2;
function params(a, a) { return a; }
console.log(dup, params(1, 2), 010, 0o10, "\101");
