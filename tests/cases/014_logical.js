// §13.13 Binary logical operators and short-circuit evaluation.
console.log(0 || "x", "" || 0, 1 && 2, 0 && crash(), null || undefined, "a" && "" && "b");
console.log(!0, !"", !"0", ![], !{}, !!NaN, !!-1, !!0n, !!1n, !!document_like());
let n = 0;
const bump = () => (n++, true);
false && bump(); true || bump(); true && bump(); false || bump();
console.log(n);
function document_like() { return undefined; }
function crash() { throw new Error("should not run"); }
