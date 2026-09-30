// §20.2.1 Function constructor and dynamic functions (global scope).
const add = new Function("a", "b", "return a + b");
console.log(add(2, 3), add.length, add.name);
const x = "module-ish";
var gx = "global";
const readG = Function("return typeof x + ':' + gx");
console.log(readG());
console.log(Function("a, b = 2", "...rest", "return a + b + rest.length")(1, undefined, 9, 9));
try { Function("return }"); } catch (e) { console.log(e.name); }
console.log(new Function().toString().replace(/\s+/g, " "));
const Gen = Object.getPrototypeOf(function* () {}).constructor;
console.log([...new Gen("yield 1; yield 2")()].join(), Gen.name);
const AsyncFn = Object.getPrototypeOf(async function () {}).constructor;
new AsyncFn("return 'async ctor'")().then(console.log);
