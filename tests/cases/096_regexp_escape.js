// RegExp.escape (ES2025) and dynamic pattern building.
console.log(RegExp.escape("a.b*c"), RegExp.escape("(x)"), RegExp.escape("foo"), RegExp.escape("1+1=2"));
const needle = "$5.00 (sale)";
console.log(new RegExp(RegExp.escape(needle)).test("now $5.00 (sale)!"));
console.log(RegExp.escape("\n").length > 1, RegExp.escape(" ").length);
