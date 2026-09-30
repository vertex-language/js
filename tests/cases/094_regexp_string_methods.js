// match, matchAll, split, search, and RegExp.prototype[Symbol.*].
console.log("a1b2c3".match(/\d/g).join(), "abc".match(/x/g), "a1".match(/(\d)/).index);
const all = [..."k1=v1;k2=v2".matchAll(/(\w+)=(\w+)/g)].map(m => m[1] + ":" + m[2] + "@" + m.index);
console.log(all.join(" "));
try { "x".matchAll(/x/); } catch (e) { console.log(e.name); }
console.log("a, b ,c".split(/\s*,\s*/).join("|"), "abc".split(/(?:)/u).join("|"), "test".split(/(t)/).join("|"));
console.log(typeof RegExp.prototype[Symbol.match], typeof RegExp.prototype[Symbol.replace], typeof RegExp.prototype[Symbol.split]);
const custom = { [Symbol.replace](s, r) { return "custom:" + s + r; } };
console.log("abc".replace(custom, "!"));
const empty = /(?:)/g;
console.log("abc".replace(empty, "-"), "😀".replace(/(?:)/gu, "-"));
console.log(RegExp.prototype.toString.call(/a\/b/), /[/]/.source);
