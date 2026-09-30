// §9.5 job queue: promise reactions run in FIFO order after the script.
console.log("script start");
Promise.resolve().then(() => console.log("p1"));
queueMicrotask(() => console.log("qm"));
Promise.resolve().then(() => { console.log("p2"); Promise.resolve().then(() => console.log("p2 nested")); }).then(() => console.log("p2 chained"));
new Promise(r => { console.log("executor sync"); r(); }).then(() => console.log("p3"));
(async () => { console.log("async body sync"); await undefined; console.log("async resumed"); })();
const resolvedWithPromise = new Promise(r => r(Promise.resolve("inner")));
resolvedWithPromise.then(v => console.log("adopted", v));
Promise.resolve("direct").then(v => console.log(v));
console.log("script end");
