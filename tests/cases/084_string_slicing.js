// §22.1.3 String.prototype.slice/substring/substr/at/charAt/charCodeAt.
const s = "Hello, World";
console.log(s.slice(0, 5), s.slice(-5), s.slice(7, -1), s.slice(5, 2), s.slice(100));
console.log(s.substring(0, 5), s.substring(5, 0), s.substring(-3, 2), s.substring(7));
console.log(s.substr(7, 3), s.substr(-5, 2), s.substr(3));
console.log(s.at(0), s.at(-1), s.at(99), s.charAt(1), s.charAt(99) === "", s.charCodeAt(0), s.charCodeAt(99));
console.log(s[4], s[-1], s.length, "".length, "😀".length, "😀".codePointAt(0), "😀".charCodeAt(0));
