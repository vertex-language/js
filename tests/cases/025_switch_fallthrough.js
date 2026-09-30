// §14.12.4 switch fallthrough, default in the middle, lexical scope of cases.
function run(v) {
  const out = [];
  switch (v) {
    case "a": out.push("a");
    default: out.push("default");
    case "b": out.push("b"); break;
    case "c": out.push("c");
  }
  return out.join(">");
}
console.log(run("a"), run("b"), run("c"), run("z"));
let order = [];
const t = (x) => { order.push(x); return x; };
switch (t(3)) { case t(1): case t(3): case t(5): break; }
console.log(order.join(","));
switch (1) { case 1: { let scoped = "block"; console.log(scoped); } }
