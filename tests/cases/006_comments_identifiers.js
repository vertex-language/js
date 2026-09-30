// §12.4 comments, §12.7 identifier names (unicode, $, _), reserved words as property names.
/* block
   comment */
let $ = 1, _ = 2, café = 3, π = 3.14, \u0061bc = "esc";
console.log($, _, café, π, abc); // trailing
const o = { if: 1, class: 2, new: 3, default: 4, let: 5, await: 6, yield: 7 };
console.log(o.if + o.class + o.new + o.default, o.let, o.await, o.yield);
let async = "a", of = "o", get = "g", set = "s", static_ = "st";
console.log(async, of, get, set, static_);
console.log(1 /* inline */ + 2);
<!-- html open comment (Annex B)
console.log("after html comment");
