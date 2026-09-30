// §27.7 async functions and await ordering.
const log = [];
async function a() { log.push("a start"); await null; log.push("a after await"); return "A"; }
async function b() { log.push("b start"); const v = await a(); log.push("b got " + v); }
b().then(() => { log.push("b done"); console.log(log.join(" | ")); });
log.push("sync end");
async function ret() { return 1; }
console.log(ret() instanceof Promise, Object.prototype.toString.call(ret));
const arrow = async x => x * 2;
arrow(21).then(v => console.log("arrow", v));
class K { async m() { return this.v; } v = "method"; }
new K().m().then(v => console.log(v));
async function thenable() { return await { then(r) { r("thenable resolved"); } }; }
thenable().then(console.log);
