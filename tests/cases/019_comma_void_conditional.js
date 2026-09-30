// §13.16 comma, §13.5.2 void, §13.14 conditional operator.
let x = (1, 2, 3);
console.log(x, void 0, void "anything", typeof void 0);
console.log(true ? "yes" : "no", 0 ? "yes" : "no", null ? 1 : undefined ? 2 : 3);
const grade = s => s >= 90 ? "A" : s >= 80 ? "B" : s >= 70 ? "C" : "F";
console.log(grade(95), grade(85), grade(72), grade(10));
let k = 0;
for (let i = 0, j = 10; i < j; i++, j--) k++;
console.log(k);
