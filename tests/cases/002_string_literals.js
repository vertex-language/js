// §12.9.4 String literals and escape sequences.
console.log('single', "double", 'it\'s', "say \"hi\"");
console.log("tab[\t] nl-len", "a\nb".length, "\\".length);
console.log("\x41\x42", "\u0043", "\u{1F600}".length, "\u{44}");
console.log("\0".charCodeAt(0), "\v".charCodeAt(0), "\f".charCodeAt(0), "\b".charCodeAt(0));
console.log("line \
continued");
console.log("\u2028".length, "\u2029".charCodeAt(0));
console.log("é" === "\u00e9", "e\u0301".length);
