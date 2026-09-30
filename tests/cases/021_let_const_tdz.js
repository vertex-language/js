// §14.3.1 let/const and the temporal dead zone.
try { console.log(early); } catch (e) { console.log(e.name); }
let early = 1;
{
  try { typeof inBlock; } catch (e) { console.log("typeof in TDZ:", e.name); }
  let inBlock = 2;
  console.log(inBlock);
}
function f() { return later; }
try { f(); } catch (e) { console.log(e.constructor === ReferenceError); }
let later = "ok";
console.log(f());
try { let x = x + 1; } catch (e) { console.log("self-ref", e.name); }
try { eval("let dup = 1; let dup = 2;"); } catch (e) { console.log(e.name); }
