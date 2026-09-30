// §6.1.6.1.20 Number::toString: shortest round-trip representation.
const nums = [0.1, 0.2, 0.30000000000000004, 1 / 3, 2 / 3, 100, 1e20, 1e21, 1.5e-7, 0.000001, 1e-7, 123e-20, 2 ** 64, 2 ** -10, 4.35, 0.1 * 3, 1.1 * 1.1, 9007199254740993, 5e-324, 1.7976931348623157e308, 12345678.9, -1.5e300];
console.log(nums.map(String).join(" "));
console.log(String(-0), (-0).toString(), `${-0}`, [-0].join(), JSON.stringify(-0), JSON.stringify([-0]));
console.log(String(NaN), String(Infinity), 1e300 * 1e10);
console.log(0.1 + 0.7, 1.23e5, 1.23e-5, 100 / 3);
