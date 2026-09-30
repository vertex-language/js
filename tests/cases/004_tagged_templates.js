// §13.3.11 Tagged templates, raw strings, template object caching.
function tag(strings, ...vals) {
  return strings.length + "|" + strings.join("_") + "|" + vals.join(",");
}
console.log(tag`a${1}b${2}c`);
console.log(tag`${"x"}`);
function raw(s) { return s.raw[0] + " / " + s[0]; }
console.log(raw`\n\t`.length, raw`x\u0041`);
function bad(s) { return String(s[0]) + " " + s.raw[0]; }
console.log(bad`\unicode`);
const seen = [];
function keep(s) { seen.push(s); }
for (let i = 0; i < 2; i++) keep`same`;
console.log(seen[0] === seen[1], Object.isFrozen(seen[0]));
console.log(String.raw`C:\path\${1 + 1}`);
