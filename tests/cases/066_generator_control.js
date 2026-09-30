// §27.5.3 generator return/throw, finally blocks, yield* delegation.
function* g() {
  try { yield 1; yield 2; } finally { console.log("cleanup"); }
}
const a = g();
a.next();
console.log(JSON.stringify(a.return("early")), JSON.stringify(a.next()));
function* catcher() { while (true) { try { yield "ok"; } catch (e) { console.log("caught", e); } } }
const c = catcher();
c.next();
console.log(c.throw("boom").value);
const unstarted = g();
try { unstarted.throw(new Error("x")); } catch (e) { console.log("thrown out:", e.message); }
function* inner() { const x = yield "i1"; console.log("inner got", x); return "inner-ret"; }
function* outer() { const r = yield* inner(); console.log("delegate returned", r); yield "o1"; }
const o = outer();
console.log(o.next().value);
console.log(o.next("X").value);
function* running() { try { r.next(); } catch (e) { yield e.name; } }
const r = running();
console.log(r.next().value);
function* fin() { try { yield 1; } finally { yield "from finally"; } }
const f = fin(); f.next();
console.log(JSON.stringify(f.return("R")), JSON.stringify(f.next()));
