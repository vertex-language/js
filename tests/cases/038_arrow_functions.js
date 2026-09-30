// §15.3 arrow functions: lexical this/arguments, no prototype, not constructible.
const obj = {
  val: 42,
  regular() { return [1].map(function () { return this; })[0] === undefined ? "undef" : "global"; },
  arrow() { return [1].map(() => this.val)[0]; },
};
console.log(obj.arrow());
const a = () => {};
console.log(a.prototype, a.hasOwnProperty("prototype"));
try { new a(); } catch (e) { console.log(e.name); }
const ret = () => ({ x: 1 });
console.log(ret().x, (x => x * 2)(4), ((a, b) => a - b)(5, 3));
const nested = () => () => () => "deep";
console.log(nested()()());
function Timer() { this.t = 0; const tick = () => { this.t++; }; tick(); tick(); return this.t; }
console.log(new Timer() instanceof Timer, Timer.call({}));
