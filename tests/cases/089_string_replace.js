// replace/replaceAll with strings, patterns, $ substitutions, and functions.
console.log("aaa".replace("a", "b"), "aaa".replaceAll("a", "b"), "aaa".replace(/a/g, "c"));
console.log("John Smith".replace(/(\w+)\s(\w+)/, "$2, $1"), "abc".replace("b", "[$&]"), "abc".replace("b", "[$`|$']"), "abc".replace("b", "$$"));
console.log("2024-01-15".replace(/(?<y>\d+)-(?<m>\d+)-(?<d>\d+)/, "$<d>/$<m>/$<y>"));
console.log("a1b22c333".replace(/\d+/g, (m, off) => `<${m.length}@${off}>`));
console.log("x-y-z".replace(/(\w)-(\w)/g, (m, p1, p2) => p2 + p1));
try { "a".replaceAll(/a/, "b"); } catch (e) { console.log(e.name); }
console.log("".replace("", "start"), "abc".replaceAll("", "-"), "aaaa".replace(/aa/g, "b"), "abc".replace("x", "y"));
console.log("$1".replace(/(\$)1/, "$1$1"), "abc".replace(/b/, "$0"), "abc".replace(/(b)/, "$01$2"));
