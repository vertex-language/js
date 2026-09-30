// §27.1 iteration protocols: custom iterables and iterators.
class Range {
  constructor(from, to) { this.from = from; this.to = to; }
  [Symbol.iterator]() {
    let cur = this.from, to = this.to;
    return { next: () => cur <= to ? { value: cur++, done: false } : { value: undefined, done: true } };
  }
}
console.log([...new Range(1, 5)].join(","), Array.from(new Range(3, 4)).join(","));
const it = [10, 20][Symbol.iterator]();
console.log(JSON.stringify(it.next()), JSON.stringify(it.next()), JSON.stringify(it.next()));
console.log(typeof it[Symbol.iterator], it[Symbol.iterator]() === it);
const s = "ab"[Symbol.iterator]();
console.log(s.next().value, s.next().value, s.next().done);
const m = new Map([[1, "one"]]).entries();
console.log(m.next().value.join(":"));
const proto = Object.getPrototypeOf(Object.getPrototypeOf([][Symbol.iterator]()));
console.log(typeof proto[Symbol.iterator], Object.prototype.toString.call([].values()));
const [a, b] = new Range(7, 100);
console.log(a, b);
