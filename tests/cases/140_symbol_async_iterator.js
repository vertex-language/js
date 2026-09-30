// Async iteration protocol details: return() on early exit, sync-to-async wrapping.
(async () => {
  const closed = [];
  const src = {
    [Symbol.asyncIterator]() {
      let i = 0;
      return {
        next: async () => ({ value: i++, done: false }),
        return: async () => { closed.push("closed"); return { done: true }; },
      };
    },
  };
  for await (const v of src) { if (v === 2) break; }
  console.log(closed.join());
  const rejecting = [Promise.reject(new Error("rejected elem"))];
  try { for await (const v of rejecting) {} } catch (e) { console.log(e.message); }
  const order = [];
  const p = (async () => { for await (const v of [1, 2]) order.push(v); })();
  order.push("sync");
  await p;
  console.log(order.join());
})();
