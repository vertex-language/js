// §22.1.3 indexOf/lastIndexOf/includes/startsWith/endsWith/search.
const s = "the quick brown fox jumps over the lazy dog";
console.log(s.indexOf("the"), s.indexOf("the", 1), s.lastIndexOf("the"), s.indexOf("cat"), s.indexOf(""), s.lastIndexOf("", 3));
console.log(s.includes("fox"), s.includes("Fox"), s.startsWith("the"), s.startsWith("quick", 4), s.endsWith("dog"), s.endsWith("lazy", 38));
console.log(s.search(/o/), s.search("brown"), s.search(/zzz/));
try { s.startsWith(/the/); } catch (e) { console.log(e.name); }
console.log("aaa".lastIndexOf("a", -5), "abc".indexOf("c", -10), "abc".includes(""));
