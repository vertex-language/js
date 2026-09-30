// Async error propagation: throw in async fn, await rejected, try/catch around await.
async function fails() { throw new TypeError("async boom"); }
fails().catch(e => console.log("caught", e.name, e.message));
async function handles() {
  try { await Promise.reject(new Error("awaited reject")); }
  catch (e) { return "handled " + e.message; }
  finally { console.log("finally in async"); }
}
handles().then(console.log);
async function chain() {
  const r = await fails().catch(() => "fallback");
  return r;
}
chain().then(v => console.log("chain", v));
new Promise(() => { throw new RangeError("in executor"); }).catch(e => console.log("executor throw", e.name));
const p = new Promise((res, rej) => { res("first"); rej(new Error("ignored")); res("ignored"); });
p.then(v => console.log("settles once", v));
Promise.resolve().then(() => { throw new Error("in then"); }).then(() => console.log("skipped")).catch(e => console.log("then throw", e.message));
const self = new Promise(r => queueMicrotask(() => r(self)));
self.catch(e => console.log("self resolution", e.name));
