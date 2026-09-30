// §6.1.6.2 BigInt arithmetic, comparisons, and bitwise ops.
const big = 2n ** 100n;
console.log(String(big), String(big + 1n), String(big * big), String(-big / 3n));
console.log(String(7n / 2n), String(-7n / 2n), String(7n % 3n), String(-7n % 3n), String(2n ** 0n));
console.log(String(0xffn), String(0b101n), String(0o17n), String(123456789012345678901234567890n * 10n));
console.log(String(5n & 3n), String(5n | 3n), String(5n ^ 3n), String(~5n), String(1n << 70n), String(-9n >> 1n));
console.log(1n < 2n, 2n > 1, 1n == 1, 1n === 1, 0n == false, 10n > 9.5, [3n, 1, 2n].sort().map(String).join());
try { 1n / 0n; } catch (e) { console.log(e.name); }
try { 1n + 1; } catch (e) { console.log(e.name); }
try { 1n >>> 1n; } catch (e) { console.log(e.name); }
try { +1n; } catch (e) { console.log(e.name); }
console.log(String(-(-5n)), String(2n ** 64n - 1n), (123n).toString(16), (-255n).toString(2), typeof Object(1n));
