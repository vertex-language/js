// §25.5.2 JSON.stringify: types, escaping, indentation.
console.log(JSON.stringify({ a: 1, b: "s", c: true, d: null, e: [1, "2"], f: { g: {} } }));
console.log(JSON.stringify("he said \"hi\"\n\t\u0001"), JSON.stringify(" \ud800"), JSON.stringify("é😀"));
console.log(JSON.stringify(undefined), JSON.stringify(() => {}), JSON.stringify(Symbol()), JSON.stringify([undefined, () => {}, Symbol()]));
console.log(JSON.stringify({ u: undefined, f() {}, [Symbol()]: 1, k: 1 }), JSON.stringify(NaN), JSON.stringify([Infinity, -Infinity]));
console.log(JSON.stringify(new Date(0)), JSON.stringify(new String("s")), JSON.stringify(new Number(3)), JSON.stringify(new Boolean(false)));
console.log(JSON.stringify({ a: [1, { b: 2 }] }, null, 2));
console.log(JSON.stringify([1, [2]], null, "--"), JSON.stringify({ a: 1 }, null, 20).split("\n")[1].length, JSON.stringify({}, null, 2), JSON.stringify([], null, 2));
console.log(JSON.stringify(new Map([[1, 2]])), JSON.stringify(/re/), JSON.stringify(Object.create({ inh: 1 })));
