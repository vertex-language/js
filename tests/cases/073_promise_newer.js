// Promise.withResolvers (ES2024) and Promise.try (ES2025); thenable adoption.
const { promise, resolve, reject } = Promise.withResolvers();
promise.then(v => console.log("withResolvers", v));
resolve("done");
Promise.try(() => 5).then(v => console.log("try value", v));
Promise.try(() => { throw new Error("sync throw"); }).catch(e => console.log("try caught", e.message));
Promise.try((a, b) => a + b, 2, 3).then(v => console.log("try args", v));
const thenable = { then(onF) { onF("from thenable"); } };
Promise.resolve(thenable).then(v => console.log(v));
const p = Promise.resolve(1);
console.log(Promise.resolve(p) === p, typeof Promise.prototype.finally);
