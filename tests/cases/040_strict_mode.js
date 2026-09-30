// §11.2.2 strict mode semantics.
"use strict";
function t() { return this; }
console.log(t() === undefined);
try { undeclared = 1; } catch (e) { console.log("implicit global:", e.name); }
const frozen = Object.freeze({ a: 1 });
try { frozen.a = 2; } catch (e) { console.log("frozen write:", e.name); }
try { delete Object.prototype; } catch (e) { console.log("delete nonconfig:", e.name); }
const getterOnly = { get x() { return 1; } };
try { getterOnly.x = 5; } catch (e) { console.log("getter only:", e.name); }
try { eval("with ({}) {}"); } catch (e) { console.log("with:", e.name); }
try { eval("var x = 010;"); } catch (e) { console.log("octal:", e.name); }
try { eval("function f(a, a) {}"); } catch (e) { console.log("dup params:", e.name); }
eval("var evalVar = 1;");
console.log(typeof evalVar);
try { "str".length = 1; } catch (e) { console.log("primitive write:", e.name); }
try { (1).prop = 1; } catch (e) { console.log("number prop:", e.name); }
