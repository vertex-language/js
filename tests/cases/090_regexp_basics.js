// §22.2 RegExp construction, exec, test, lastIndex, source, flags.
const re = /(\d+)-(\d+)/;
const m = re.exec("range 10-20 end");
console.log(m[0], m[1], m[2], m.index, m.input, m.length);
console.log(re.test("a-b"), /^abc$/.test("abc"), /abc/.exec("xyz"));
const g = /o/g;
console.log(g.test("foo"), g.lastIndex, g.test("foo"), g.lastIndex, g.test("foo"), g.lastIndex);
const r2 = new RegExp("a+b", "gi");
console.log(r2.source, r2.flags, r2.global, r2.ignoreCase, r2.multiline, String(r2));
console.log(new RegExp("/").source, String(new RegExp("")), new RegExp(/x/g, "i").flags, RegExp(/y/) instanceof RegExp);
try { new RegExp("("); } catch (e) { console.log(e.name); }
try { new RegExp("a", "gg"); } catch (e) { console.log(e.name); }
console.log(/[a-c]+/.exec("xxabcabx")[0], /\bfoo\b/.test("a foo b"), /\Bfoo/.test("afoo"), /a.c/.test("a\nc"));
console.log(/\d{2,3}/.exec("1 12345")[0], /a*?b/.exec("aaab")[0], /(a)|(b)/.exec("b")[1], /[^abc]/.exec("abcd")[0]);
console.log(/A\x42\cJ/.test("AB\n"), /[\s\S]/.test("\n"), /\w\W\d\D/.test("a!1x"));
