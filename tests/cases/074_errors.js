// §20.5 Error objects: constructors, name, message, cause, prototype chain.
const types = [Error, TypeError, RangeError, SyntaxError, ReferenceError, EvalError, URIError];
for (const T of types) {
  const e = new T("msg");
  console.log(e.name, e.message, e instanceof Error, e instanceof T, Object.getPrototypeOf(T) === (T === Error ? Function.prototype : Error));
}
const noNew = Error("called");
console.log(noNew instanceof Error, noNew.message);
const withCause = new Error("outer", { cause: "inner reason" });
console.log(withCause.cause, "cause" in new Error("x"), "cause" in new Error("x", {}));
console.log(new Error().message === "", Object.hasOwn(new Error(), "message"), Object.hasOwn(new Error("m"), "message"));
console.log(Object.getOwnPropertyDescriptor(new Error("m"), "message").enumerable);
console.log(typeof new Error("s").stack);
try { decodeURIComponent("%"); } catch (e) { console.log(e.name); }
try { new Array(-1); } catch (e) { console.log(e.name); }
try { (1).toFixed(101); } catch (e) { console.log(e.name); }
try { JSON.parse("{bad"); } catch (e) { console.log(e.name); }
