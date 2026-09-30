// §21.2 BigInt constructor, asIntN/asUintN, and conversions.
console.log(String(BigInt(42)), String(BigInt("0x1f")), String(BigInt("  123  ")), String(BigInt(true)), String(BigInt("")));
try { BigInt(1.5); } catch (e) { console.log(e.name); }
try { BigInt("1.5"); } catch (e) { console.log(e.name); }
try { new BigInt(1); } catch (e) { console.log(e.name); }
console.log(String(BigInt.asIntN(8, 255n)), String(BigInt.asUintN(8, -1n)), String(BigInt.asIntN(64, 2n ** 63n)), String(BigInt.asUintN(64, -1n)));
console.log(Number(2n ** 53n + 1n), Number(-12n), parseInt("99n"), String(BigInt(Number.MAX_SAFE_INTEGER) + 2n));
console.log(`${10n}`, 10n + "", JSON.stringify({ toJSON() { return String(10n); } }));
try { JSON.stringify(1n); } catch (e) { console.log(e.name); }
console.log((1234567n).toLocaleString === undefined ? "no" : "has toLocaleString", BigInt.prototype[Symbol.toStringTag]);
