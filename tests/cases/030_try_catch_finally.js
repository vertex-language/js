// §14.15 try/catch/finally and completion values.
function a() { try { return "try"; } finally { console.log("finally runs"); } }
console.log(a());
function b() { try { return "try"; } finally { return "finally"; } }
console.log(b());
function c() { try { throw new Error("x"); } catch (e) { return "caught " + e.message; } finally { } }
console.log(c());
function d() {
  for (let i = 0; i < 3; i++) { try { if (i === 1) break; } finally { console.log("fin", i); } }
  return "done";
}
console.log(d());
function e() { try { throw 1; } finally { return "swallowed"; } }
console.log(e());
let log = [];
try { try { throw new Error("inner"); } finally { log.push("f1"); } } catch (x) { log.push(x.message); }
console.log(log.join(","));
function nested() { try { try { throw "a"; } catch (x) { throw x + "b"; } } catch (y) { return y + "c"; } }
console.log(nested());
console.log(eval("try { 1 } finally { 2 }"), eval("L: try { 3 } catch (e) {}"));
