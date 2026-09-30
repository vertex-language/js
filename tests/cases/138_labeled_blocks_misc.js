// Miscellaneous statements: empty, debugger, labeled function-less blocks, completion values.
;;;
debugger;
console.log(eval("1; ;"), eval("var z = 3"), eval("{}"), eval("for (var i = 0; i < 2; i++) i * 10"), eval("do 5; while (false)"));
console.log(eval("switch (1) { case 1: 'one'; }"), eval("while (false);"), eval("a: { 'x'; break a; }"));
console.log(eval("if (false) 1;"), eval("L: for (;;) { 'v'; break L; }"));
