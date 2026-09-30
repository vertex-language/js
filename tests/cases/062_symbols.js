// §20.4 Symbol: uniqueness, description, registry, conversion rules.
const a = Symbol("desc"), b = Symbol("desc");
console.log(a === b, a.description, String(a), a.toString(), Symbol().description);
console.log(Symbol.for("app") === Symbol.for("app"), Symbol.keyFor(Symbol.for("app")), Symbol.keyFor(a));
try { a + ""; } catch (e) { console.log(e.name); }
try { +a; } catch (e) { console.log(e.name); }
try { new Symbol(); } catch (e) { console.log(e.name); }
const o = { [a]: 1, visible: 2 };
console.log(Object.keys(o).length, JSON.stringify(o), o[a], Object.getOwnPropertySymbols(o)[0] === a);
console.log(typeof Object(a), Object(a) == a, !!a);
console.log(typeof Symbol.iterator, String(Symbol.asyncIterator), Symbol.iterator.description);
