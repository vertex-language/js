// §19.2.1 eval: direct vs indirect, var leakage, strict eval scoping.
var x = "global";
function direct() { var x = "local"; return eval("x"); }
function indirect() { var x = "local"; return (0, eval)("x"); }
console.log(direct(), indirect());
function leak() { eval("var leaked = 1"); return typeof leaked; }
console.log(leak(), typeof leaked);
function strictEval() { "use strict"; eval("var s = 1"); return typeof s; }
console.log(strictEval());
console.log(eval("1 + 2"), eval("({ a: 1 }).a"), eval("if (true) 'if'; else 'else'"), eval(42), eval("let q = 5; q * 2"));
try { eval("}"); } catch (e) { console.log(e.name); }
const geval = eval;
geval("var fromIndirect = 'global now'");
console.log(globalThis.fromIndirect);
function lexical() { let l = "let"; return eval("l"); }
console.log(lexical(), eval("typeof this"), eval("(function(){ return this === globalThis })()"));
