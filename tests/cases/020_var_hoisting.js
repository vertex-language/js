// §14.3.2 var hoisting, function declaration hoisting, redeclaration.
console.log(typeof hoisted, v);
var v = 1;
function hoisted() { return "h"; }
console.log(hoisted(), v);
var v;
console.log(v);
function outer() {
  console.log(typeof inner, w);
  if (false) { var w = 2; }
  return inner();
  function inner() { return "inner"; }
}
console.log(outer());
var fn = "var";
function fn() {}
console.log(typeof fn);
for (var loopVar = 0; loopVar < 3; loopVar++) {}
console.log(loopVar);
