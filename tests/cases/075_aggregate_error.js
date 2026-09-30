// §20.5.7 AggregateError and Error.prototype.toString.
const ag = new AggregateError([new Error("a"), "b"], "multiple", { cause: 1 });
console.log(ag.name, ag.message, ag.errors.length, ag.errors[1], ag.cause, ag instanceof Error);
console.log(Array.isArray(ag.errors), Object.getOwnPropertyDescriptor(ag, "errors").enumerable);
const ts = Error.prototype.toString;
console.log(ts.call({ name: "N", message: "M" }), ts.call({ name: "", message: "M" }), ts.call({ name: "N", message: "" }), ts.call({}));
console.log(String(new TypeError("bad type")), String(new Error()));
const custom = new Error("x"); custom.name = "Custom";
console.log(String(custom));
try { ts.call(1); } catch (e) { console.log(e.name); }
