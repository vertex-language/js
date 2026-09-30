// Lookahead and lookbehind assertions.
console.log(/\d+(?=px)/.exec("10em 20px")[0], /\d+(?!px)/.exec("20px 30em")[0]);
console.log(/(?<=\$)\d+/.exec("cost: $42")[0], /(?<!\$)\b\d+/.exec("$5 and 7")[0]);
console.log("1234567".replace(/\B(?=(\d{3})+(?!\d))/g, ","));
console.log(/(?<=(\d)(\d))x/.exec("12x").slice(1).join(), /(?<=a(?=b)b)c/.test("abc"));
console.log("password1".match(/^(?=.*\d)(?=.*[a-z]).{8,}$/) !== null);
