// split with strings, limits, and edge cases.
console.log("a,b,,c".split(",").length, "a,b,c".split(",", 2).join("|"), "abc".split("").join("|"), "".split(",").length, "".split("").length);
console.log("abc".split().length, "a1b2c3".split(/\d/).join("|"), "a1b2c3".split(/(\d)/).join("|"));
console.log("one  two".split(" ").length, "😀x".split("").length, [..."😀x"].length);
console.log(["a", null, undefined, 1, [2, 3]].join("-"), [].join(), [1, 2].join(undefined));
