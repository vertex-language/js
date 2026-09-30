// ES2024 resizable ArrayBuffer and transfer.
const rab = new ArrayBuffer(4, { maxByteLength: 16 });
const view = new Uint8Array(rab);
console.log(rab.resizable, rab.maxByteLength, view.length);
rab.resize(12);
console.log(rab.byteLength, view.length);
try { rab.resize(32); } catch (e) { console.log(e.name); }
const fixed = new ArrayBuffer(8);
new Uint8Array(fixed)[0] = 42;
const moved = fixed.transfer(16);
console.log(fixed.detached, fixed.byteLength, moved.byteLength, new Uint8Array(moved)[0], moved.resizable);
try { new Uint8Array(fixed); } catch (e) { console.log(e.name); }
const t2 = moved.transferToFixedLength();
console.log(t2.byteLength, moved.detached);
