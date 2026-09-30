// padStart/padEnd/repeat/trim family/concat.
console.log("5".padStart(3, "0"), "abc".padEnd(6, "12"), "abc".padStart(2), "x".padStart(5), "x".padEnd(3, ""), "|" + "x".padEnd(3) + "|");
console.log("ab".repeat(3), "x".repeat(0) === "");
try { "x".repeat(-1); } catch (e) { console.log(e.name); }
try { "x".repeat(Infinity); } catch (e) { console.log(e.name); }
const ws = " \t\n ﻿hi  ";
console.log("[" + ws.trim() + "]", ws.trimStart().length, ws.trimEnd().length);
console.log("a".concat("b", 1, null), "".concat());
