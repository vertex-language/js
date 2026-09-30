// §13.15.2 Compound assignment evaluation order.
let x = 10;
x += 5; x -= 3; x *= 2; x /= 4; x %= 4;
console.log(x);
let s = "a";
s += "b"; s += 1; s += null;
console.log(s);
const log = [];
const obj = { get p() { log.push("get"); return 1; }, set p(v) { log.push("set" + v); } };
obj.p += 1;
console.log(log.join(","));
const arr = [1, 2, 3];
let i = 0;
arr[i++] += 10;
console.log(arr.join(","), i);
let a, b, c;
a = b = c = 7;
console.log(a + b + c);
