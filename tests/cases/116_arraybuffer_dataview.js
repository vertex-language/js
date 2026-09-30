// §25.1 ArrayBuffer and §25.3 DataView with endianness.
const buf = new ArrayBuffer(8);
const dv = new DataView(buf);
dv.setInt16(0, -2);
dv.setUint16(2, 0x1234, true);
dv.setFloat32(4, 1.5);
console.log(buf.byteLength, dv.getInt16(0), dv.getUint16(0), dv.getUint8(2).toString(16), dv.getUint8(3).toString(16), dv.getFloat32(4), dv.getUint16(2));
console.log(buf.slice(2, 4).byteLength, ArrayBuffer.isView(dv), ArrayBuffer.isView(buf), new DataView(buf, 2, 4).byteLength, new DataView(buf, 2).byteOffset);
try { dv.getInt32(6); } catch (e) { console.log(e.name); }
try { new DataView(buf, 9); } catch (e) { console.log(e.name); }
const d2 = new DataView(new ArrayBuffer(8));
d2.setFloat64(0, Math.PI);
console.log(d2.getFloat64(0) === Math.PI, d2.getUint8(0).toString(16));
d2.setBigInt64(0, -1n);
console.log(String(d2.getBigUint64(0)), String(d2.getBigInt64(0)));
try { ArrayBuffer(8); } catch (e) { console.log(e.name); }
