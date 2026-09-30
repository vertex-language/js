// Integration: async task queue with concurrency limit, generators, and promise ordering.
function deferredValue(v, ticks) {
  return new Promise(res => { let n = ticks; const step = () => (n-- > 0 ? queueMicrotask(step) : res(v)); step(); });
}
async function pool(tasks, limit) {
  const results = new Array(tasks.length);
  const started = [];
  let next = 0;
  async function worker(id) {
    while (next < tasks.length) {
      const i = next++;
      started.push(`w${id}:t${i}`);
      results[i] = await tasks[i]();
    }
  }
  await Promise.all(Array.from({ length: limit }, (_, id) => worker(id)));
  return { results, started };
}
const tasks = [5, 1, 3, 2, 4].map((ticks, i) => () => deferredValue(`r${i}`, ticks));
pool(tasks, 2).then(({ results, started }) => {
  console.log(results.join());
  console.log(started.length, started.slice(0, 2).join());
  return Promise.allSettled([deferredValue("x", 1), Promise.reject(new Error("y"))]);
}).then(s => console.log(s.map(r => r.status).join()));
