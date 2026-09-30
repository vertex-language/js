// §13.9, §13.12 Bitwise and shift operators (ToInt32/ToUint32).
console.log(5 & 3, 5 | 3, 5 ^ 3, ~5, ~-1, ~~3.7, ~~-3.7);
console.log(1 << 31, 1 << 32, 1 << 33, -1 >> 1, -1 >>> 0, -1 >>> 28, 256 >> 4);
console.log(2 ** 32 + 5 | 0, 2 ** 31 | 0, 4294967295 & 0xff, 1.9 | 0, -1.9 | 0);
console.log("12" << "1", NaN | 0, Infinity | 0, null ^ 7);
let f = 0b1100;
f &= 0b1010; console.log(f);
f |= 1; console.log(f);
f ^= 0xff; console.log(f);
f <<= 2; f >>= 1; f >>>= 1; console.log(f);
