// Case mapping, code points, normalize, well-formed strings.
console.log("Hello".toUpperCase(), "WORLD".toLowerCase(), "ß".toUpperCase(), "İ".toLowerCase().length, "ǅ".toLowerCase(), "Σ".toLowerCase());
console.log(String.fromCharCode(72, 105), String.fromCharCode(0x1F600 & 0xffff), String.fromCodePoint(128512).length, String.fromCodePoint(65, 66));
try { String.fromCodePoint(-1); } catch (e) { console.log(e.name); }
console.log("😀".codePointAt(0), "😀".codePointAt(1), "a😀".codePointAt(1).toString(16));
console.log("é" === "é", "é".normalize() === "é", "é".normalize("NFD").length, "ﬁ".normalize("NFKC"));
console.log("ab\uD800".isWellFormed(), "ab".isWellFormed(), "ab\uD800".toWellFormed().charCodeAt(2).toString(16));
console.log(String.raw`\n${1}`, String.raw({ raw: ["a", "b", "c"] }, 1, 2));
console.log("abc".localeCompare("abd"), "b".localeCompare("a"), "a".localeCompare("a"));
