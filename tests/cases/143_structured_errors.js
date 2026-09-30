// Runtime errors thrown by the engine have the right constructor and are catchable.
const cases = {
  callNonFn: () => (1)(),
  readNull: () => null.prop,
  writeUndef: () => { undefined.x = 1; },
  newNonCtor: () => new (() => {})(),
  badLength: () => new Array(2 ** 32),
  badInstanceof: () => 1 instanceof 1,
  badIn: () => "a" in 1,
  tdz: () => { t; let t; },
  undeclared: () => nope,
  bigintMix: () => 1n + 1,
  symbolToNumber: () => Symbol() * 1,
  spreadNonIterable: () => [...1],
  constAssign: () => { const c = 1; c = 2; },
  classCall: () => { class C {} C(); },
  badRegex: () => new RegExp("["),
  badJSON: () => JSON.parse("{"),
  toFixedRange: () => (1).toFixed(-1),
  stackOverflow: () => { const f = () => f(); f(); },
};
for (const [name, fn] of Object.entries(cases)) {
  try { fn(); console.log(name, "no error"); } catch (e) { console.log(name, e.constructor.name, e instanceof Error, typeof e.message); }
}
