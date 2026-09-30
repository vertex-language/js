// §10.1.11 OrdinaryOwnPropertyKeys: integer indices ascending, then strings, then symbols, in creation order.
const o = {};
o.z = 1; o[10] = 1; o.a = 1; o[2] = 1; o["-1"] = 1; o["01"] = 1; o[4294967294] = 1; o[4294967295] = 1; o[1.5] = 1;
const s1 = Symbol("1"), s2 = Symbol("2");
o[s2] = 1; o[s1] = 1;
console.log(Object.keys(o).join(","));
console.log(Reflect.ownKeys(o).map(String).join(","));
delete o.z; o.z = 2;
console.log(Object.keys(o).slice(-1)[0]);
console.log(JSON.stringify({ b: 1, 1: 1, a: 1, 0: 1 }));
class K { static b; static a; }
console.log(Object.keys(K).join(","));
