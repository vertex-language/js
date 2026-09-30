// Capture groups, named groups, backreferences, non-capturing groups.
const m = /(?<year>\d{4})-(?<month>\d{2})/.exec("on 2024-03");
console.log(m.groups.year, m.groups.month, m[1], Object.getPrototypeOf(m.groups));
console.log(/(\w)\1/.exec("hello")[0], /(?<q>['"]).*?\k<q>/.exec(`say "hi" 'x'`)[0]);
console.log(/(?:ab)+/.exec("ababab")[0], /(a)(?:b)(c)/.exec("abc").length);
console.log(/(a)?b/.exec("b")[1], /(a)|b/.exec("b").length);
console.log(/(z)((a+)?(b+)?(c))*/.exec("zaacbbbcac").join("|"));
console.log(/\1(a)/.exec("aa")[0], /(?<a>x)|(?<a>y)/.exec("y").groups.a);
