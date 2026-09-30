// §14.6 if, §14.12 switch (strict equality matching).
function kind(x) {
  if (x > 0) return "pos";
  else if (x < 0) return "neg";
  else return "zero";
}
console.log(kind(3), kind(-1), kind(0));
function sw(v) {
  switch (v) {
    case 1: return "one";
    case "1": return "string one";
    case true: return "true";
    case null: return "null";
    default: return "default";
  }
}
console.log(sw(1), sw("1"), sw(true), sw(null), sw(undefined));
if (0) console.log("no"); else console.log("dangling else");
