// keys/values/entries and live iteration.
const a = ["a", "b"];
console.log([...a.keys()].join(), [...a.values()].join(), [...a.entries()].map(e => e.join(":")).join());
console.log([...[, "x"].keys()].join(), Object.keys([, "x"]).join());
console.log(a[Symbol.iterator] === a.values, typeof a.entries().next);
const live = [1];
const it = live.values();
live.push(2);
console.log(it.next().value, it.next().value, it.next().done);
const typed = [...new Uint8Array([7, 8]).entries()].map(e => e.join("=")).join();
console.log(typed);
