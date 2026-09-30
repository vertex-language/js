// ES2024 Array.fromAsync.
async function* gen() { yield 1; await null; yield 2; }
(async () => {
  console.log((await Array.fromAsync(gen())).join());
  console.log((await Array.fromAsync([Promise.resolve("a"), "b"])).join());
  console.log((await Array.fromAsync([1, 2], async x => x * 10)).join());
  console.log((await Array.fromAsync({ length: 2, 0: "x", 1: Promise.resolve("y") })).join());
})();
