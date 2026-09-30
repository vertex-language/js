// ES2025 additions: Float16Array, Math.f16round, JSON modules aside, Promise.try covered elsewhere.
console.log(Math.f16round(1.337), Math.f16round(65520), Math.f16round(5e-8));
const f16 = new Float16Array([1.5, 0.1, 70000]);
console.log(f16.join(), Float16Array.BYTES_PER_ELEMENT, new DataView(new ArrayBuffer(2)).getFloat16(0));
const dv = new DataView(new ArrayBuffer(2));
dv.setFloat16(0, 2.5);
console.log(dv.getFloat16(0), dv.getUint16(0).toString(16));
