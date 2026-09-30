// §23.2 TypedArrays: element types, conversion, views over shared buffers.
const types = [Int8Array, Uint8Array, Uint8ClampedArray, Int16Array, Uint16Array, Int32Array, Uint32Array, Float32Array, Float64Array];
console.log(types.map(T => T.name + ":" + T.BYTES_PER_ELEMENT).join(" "));
console.log(types.map(T => new T([300, -1, 1.7])).map(a => a.join("/")).join(" "));
const buf = new ArrayBuffer(4);
const u8 = new Uint8Array(buf), u32 = new Uint32Array(buf);
u32[0] = 0x01020304;
console.log(u8.join(), u8.buffer === buf, u8.byteLength, new Uint16Array(buf, 2, 1).length);
console.log(new Float64Array([0.1])[0], new Float32Array([0.1])[0], new Uint8ClampedArray([255.5, 0.5, 1.5, -5])[0]);
const big = new BigInt64Array([1n, -1n]);
console.log(String(big[1]), String(new BigUint64Array(big.buffer)[1]));
try { new Uint16Array(new ArrayBuffer(3)); } catch (e) { console.log(e.name); }
u8[10] = 5;
console.log(u8[10], u8.length, Object.keys(u8).join());
