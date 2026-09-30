// §27.6 async generators and for await...of.
async function* ticker(n) { for (let i = 0; i < n; i++) { await null; yield i; } }
(async () => {
  const seen = [];
  for await (const t of ticker(3)) seen.push(t);
  console.log("ticker", seen.join());
  const fromSync = [];
  for await (const v of [Promise.resolve("p1"), "plain", Promise.resolve("p2")]) fromSync.push(v);
  console.log("sync iterable", fromSync.join());
  const ag = ticker(5);
  console.log(JSON.stringify(await ag.next()), JSON.stringify(await ag.return("stop")), JSON.stringify(await ag.next()));
  const custom = { [Symbol.asyncIterator]() { let i = 0; return { next: async () => ({ value: i, done: i++ >= 2 }) }; } };
  let s = 0;
  for await (const v of custom) s += v + 10;
  console.log("custom", s);
  console.log(Object.prototype.toString.call(ticker(1)), typeof ticker(1)[Symbol.asyncIterator]);
  async function* thrower() { yield 1; throw new Error("agen err"); }
  try { for await (const x of thrower()) {} } catch (e) { console.log("caught", e.message); }
})();
