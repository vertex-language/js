// §13.2.5 object spread and §14.3.3 object rest.
const a = { x: 1, y: 2 };
const b = { ...a, y: 3, z: 4 };
console.log(JSON.stringify(b));
console.log(JSON.stringify({ ...null, ...undefined, ..."hi", ...[9], ...5 }));
const withGetter = { get g() { return "evaluated"; } };
const copy = { ...withGetter };
console.log(typeof Object.getOwnPropertyDescriptor(copy, "g").value);
const { x, ...rest } = { x: 1, y: 2, z: 3 };
console.log(x, JSON.stringify(rest));
const proto = { inherited: 1 };
const own = Object.create(proto); own.mine = 2;
console.log(JSON.stringify({ ...own }));
const s = Symbol("s");
const withSym = { ...{ [s]: "sym" } };
console.log(withSym[s]);
const hidden = Object.defineProperty({}, "h", { value: 1, enumerable: false });
console.log(Object.keys({ ...hidden }).length);
