// §14.14 throw any value; §14.15 optional catch binding and catch param destructuring.
for (const v of [1, "str", null, undefined, true]) {
  try { throw v; } catch (e) { console.log(typeof e, String(e)); }
}
try { throw { code: 42, msg: "obj" }; } catch ({ code, msg }) { console.log(code, msg); }
try { throw [1, 2]; } catch ([a, b]) { console.log(a + b); }
try { JSON.parse("{"); } catch { console.log("no binding"); }
try { null.x; } catch (e) { console.log(e instanceof TypeError, e.constructor.name); }
try { undefinedFunction(); } catch (e) { console.log(e.name); }
try { (void 0)(); } catch (e) { console.log(e.name); }
