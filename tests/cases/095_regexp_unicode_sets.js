// Unicode property escapes (u) and set notation (v flag, ES2024).
console.log(/\p{L}+/u.exec("123héllo")[0], /\p{Lu}/u.test("a"), /\p{Lu}/u.test("A"), /\P{L}/u.exec("ab1")[0]);
console.log(/\p{Script=Greek}+/u.exec("abc αβγ")[0], /\p{Emoji_Presentation}/u.test("😀"), /^\p{Nd}+$/u.test("٣٤"));
console.log(/[\p{L}--[a-z]]/v.exec("abcD")[0], /[[a-z]&&[aeiou]]+/v.exec("xyzaei")[0], /[\q{abc|d}]/v.exec("zabc")[0]);
console.log(/\p{RGI_Emoji}/v.test("👍🏽"), /x/v.unicodeSets, /x/v.flags);
try { new RegExp("\\p{Nope}", "u"); } catch (e) { console.log(e.name); }
