// §27.2.4 Promise.all/allSettled/race/any.
const delay = (v, fail) => new Promise((res, rej) => queueMicrotask(() => fail ? rej(new Error(v)) : res(v)));
Promise.all([1, delay("b"), Promise.resolve("c")]).then(v => console.log("all", v.join()));
Promise.all([delay("x"), delay("bad", true)]).catch(e => console.log("all rejects", e.message));
Promise.all([]).then(v => console.log("all empty", v.length));
Promise.allSettled([delay("ok"), delay("no", true)]).then(r => console.log("settled", r.map(x => x.status + ":" + (x.value ?? x.reason.message)).join()));
Promise.race([delay("slow"), "fast"]).then(v => console.log("race", v));
Promise.any([delay("e1", true), delay("win"), delay("e2", true)]).then(v => console.log("any", v));
Promise.any([Promise.reject(1), Promise.reject(2)]).catch(e => console.log("any fails", e.constructor.name, e.errors.join()));
Promise.reject(new Error("r")).catch(e => e.message).then(v => console.log("recovered", v));
Promise.resolve(1).finally(() => "ignored").then(v => console.log("finally passthrough", v));
Promise.reject(new Error("f")).finally(() => console.log("finally on reject")).catch(e => console.log("still rejected", e.message));
