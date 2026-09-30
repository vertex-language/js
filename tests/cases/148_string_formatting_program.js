// Integration: a tiny table formatter using strings, arrays, and numbers.
const rows = [
  { item: "Widget", qty: 3, price: 2.5 },
  { item: "Gadget", qty: 10, price: 0.99 },
  { item: "Thingamajig", qty: 1, price: 120 },
];
const cols = ["item", "qty", "price", "total"];
const data = rows.map(r => ({ ...r, total: (r.qty * r.price).toFixed(2), price: r.price.toFixed(2) }));
const widths = cols.map(c => Math.max(c.length, ...data.map(r => String(r[c]).length)));
const line = cells => cells.map((c, i) => i === 0 ? String(c).padEnd(widths[i]) : String(c).padStart(widths[i])).join(" | ");
console.log(line(cols));
console.log(widths.map(w => "-".repeat(w)).join("-+-"));
for (const r of data) console.log(line(cols.map(c => r[c])));
const grand = data.reduce((s, r) => s + Number(r.total), 0);
console.log("grand total", grand.toFixed(2));
