// Date.parse of ISO formats, invalid dates, and conversions.
console.log(Date.parse("2024-03-10T12:00:00Z"), Date.parse("2024-03-10T12:00:00.5+02:00"), Date.parse("2024-03-10"), Date.parse("2024-03"), Date.parse("2024"));
console.log(Date.parse("+002024-01-01T00:00:00Z"), Date.parse("-000001-01-01T00:00:00Z"));
const bad = new Date("not a date");
console.log(isNaN(bad), bad.getTime(), String(bad), bad.toJSON());
try { bad.toISOString(); } catch (e) { console.log(e.name); }
console.log(new Date("2024-01-01T00:00:00Z").getTime() === Date.UTC(2024, 0, 1), new Date(NaN).getUTCFullYear());
const d = new Date(0);
console.log(d.setTime(86400000), d.toISOString().slice(0, 10), d[Symbol.toPrimitive]("number"), typeof d[Symbol.toPrimitive]("default"));
console.log(new Date(2024, 0, 31, 12).getMonth(), new Date(2024, 0, 31, 12).getDate());
