// §25.5.1 JSON.parse and reviver.
const o = JSON.parse('{"a":[1,2,{"b":null}],"c":"\\u0041\\n","d":-1.5e2,"e":true}');
console.log(o.a[2].b, o.c.length, o.d, o.e, Array.isArray(o.a));
console.log(JSON.parse("1"), JSON.parse('"s"'), JSON.parse("null"), JSON.parse(" [ ] ").length, JSON.parse("{}").constructor === Object);
for (const bad of ["{'a':1}", "[1,]", "01", "undefined", "NaN", '"\t"', "{a:1}", "", "1 2", '"\\x41"']) {
  try { JSON.parse(bad); console.log("accepted", bad); } catch (e) { console.log("rejected", e.name); }
}
const revived = JSON.parse('{"a":1,"b":{"c":2},"drop":3}', (k, v) => k === "drop" ? undefined : typeof v === "number" ? v + 100 : v);
console.log(JSON.stringify(revived));
const order = [];
JSON.parse('{"x":{"y":1},"z":[2]}', (k, v) => { order.push(k); return v; });
console.log(order.join("|"));
console.log(JSON.parse('{"__proto__":1}').__proto__, Object.keys(JSON.parse('{"__proto__":{}}')).join());
console.log(JSON.parse('{"a":1,"a":2}').a, JSON.parse("1e400"), JSON.parse('"\\ud83d\\ude00"'));
