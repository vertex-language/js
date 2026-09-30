// ES2026 additions: Error.isError, Uint8Array base64/hex, Array.fromAsync, Iterator.concat.
console.log(Error.isError(new TypeError()), Error.isError({ name: "Error", message: "" }), Error.isError(Object.create(Error.prototype)));
const bytes = new Uint8Array([72, 101, 108, 108, 111, 255]);
console.log(bytes.toBase64(), bytes.toHex(), bytes.toBase64({ alphabet: "base64url", omitPadding: true }));
console.log(Uint8Array.fromBase64("SGVsbG8=").join(), Uint8Array.fromHex("cafe").join());
const target = new Uint8Array(4);
console.log(JSON.stringify(target.setFromHex("0a0b")), target.join());
try { Uint8Array.fromHex("abc"); } catch (e) { console.log(e.name); }
console.log(Iterator.concat([1, 2], new Set([3])).toArray().join());
