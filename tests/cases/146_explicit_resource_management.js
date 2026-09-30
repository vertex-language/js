// ES2026 explicit resource management: using, DisposableStack, Symbol.dispose.
const log = [];
function res(name) { return { name, [Symbol.dispose]() { log.push("dispose " + name); } }; }
{
  using a = res("a");
  using b = res("b");
  log.push("body");
}
console.log(log.join(" > "));
const stack = new DisposableStack();
stack.defer(() => log.push("deferred"));
stack.use(res("c"));
stack.dispose();
console.log(log.slice(-2).join(","), stack.disposed);
try { { using x = res("x"); throw new Error("inner"); } } catch (e) { console.log("caught", e.message, log.at(-1)); }
try {
  { using bad = { [Symbol.dispose]() { throw new Error("dispose err"); } }; throw new Error("body err"); }
} catch (e) { console.log(e.constructor.name, e.error.message, e.suppressed.message); }
(async () => {
  {
    await using ar = { async [Symbol.asyncDispose]() { log.push("async disposed"); } };
  }
  console.log(log.at(-1), typeof AsyncDisposableStack);
})();
