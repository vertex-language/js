// §15.7 class definitions.
class Point {
  constructor(x, y) { this.x = x; this.y = y; }
  add(o) { return new Point(this.x + o.x, this.y + o.y); }
  toString() { return `(${this.x}, ${this.y})`; }
  get len() { return Math.hypot(this.x, this.y); }
  set len(v) { const k = v / this.len; this.x *= k; this.y *= k; }
}
const p = new Point(3, 4);
console.log(String(p.add(new Point(1, 1))), p.len);
p.len = 10;
console.log(String(p));
console.log(typeof Point, Point.name, Point.length, Object.keys(Point.prototype).length);
try { Point(1, 2); } catch (e) { console.log(e.name); }
const Anon = class {};
const Named = class Inner { who() { return Inner.name; } };
console.log(Anon.name, Named.name, new Named().who());
const desc = Object.getOwnPropertyDescriptor(Point.prototype, "add");
console.log(desc.enumerable, desc.writable, desc.configurable);
console.log(Object.getOwnPropertyDescriptor(Point, "prototype").writable);
try { new Point.prototype.add(); } catch (e) { console.log("method ctor:", e.name); }
class Empty {}
console.log(new Empty() instanceof Empty, typeof new Empty().constructor);
