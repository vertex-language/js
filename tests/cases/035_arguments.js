// §10.4.4 arguments exotic objects: mapped (sloppy) vs unmapped (strict).
function sloppy(a) { arguments[0] = "changed"; return a; }
function strict(a) { "use strict"; arguments[0] = "changed"; return a; }
console.log(sloppy("orig"), strict("orig"));
function rev(a) { a = "param"; return arguments[0]; }
console.log(rev("arg"));
function withDefault(a = 1) { arguments[0] = "changed"; return a; }
console.log(withDefault("orig"));
function info() { return arguments.length + " " + typeof arguments + " " + Array.isArray(arguments) + " " + Object.prototype.toString.call(arguments); }
console.log(info(1, 2, 3));
function toArr() { return Array.from(arguments).join("-"); }
console.log(toArr("a", "b"));
function s() { "use strict"; try { return arguments.callee; } catch (e) { return e.name; } }
console.log(s());
const arrow = () => typeof arguments;
function outer() { return (() => arguments[0])(); }
console.log(outer("lexical"));
