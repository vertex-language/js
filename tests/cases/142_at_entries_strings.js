// Object.entries/values on strings and arrays; String.prototype[Symbol.iterator]; Array.prototype.at on array-likes.
console.log(Object.entries("hi").map(e => e.join("=")).join(), Object.values("abc").join(""));
console.log(Array.prototype.at.call("xyz", -1), Array.prototype.at.call({ length: 2, 1: "b" }, -1));
console.log([..."ab"].reverse().join(""), "abc"[Symbol.iterator]().next().value);
console.log(Object.getOwnPropertyNames("ab").join(), Object.getOwnPropertyDescriptor("ab", 0).writable);
