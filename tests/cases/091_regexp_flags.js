// RegExp flags: i, m, s, u, y, d.
console.log(/abc/i.test("ABC"), /^b/m.test("a\nb"), /^b/.test("a\nb"), /a.b/s.test("a\nb"));
console.log(/^.$/.test("😀"), /^.$/u.test("😀"), /\u{1F600}/u.test("😀"), "😀".match(/./gu).length);
const y = /foo/y;
console.log(y.test("foofoo"), y.lastIndex, y.test("foo foo"), y.lastIndex);
y.lastIndex = 3;
console.log(y.exec("barfoo")[0], y.sticky);
const d = /(a)(?<name>b)?/d.exec("xab");
console.log(d.indices[0].join(), d.indices[1].join(), d.indices.groups.name.join(), /x/d.hasIndices);
console.log(/[a-z]/i.test("Q"), /\w/iu.test("ſ"), /\w/i.test("ſ"), new RegExp("x", "dgimsuy").flags);
