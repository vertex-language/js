// §21.4 Date in UTC: construction, getters, arithmetic, ISO output.
const d = new Date(Date.UTC(2024, 1, 29, 13, 45, 30, 123));
console.log(d.toISOString(), d.getTime(), d.valueOf() === +d, JSON.stringify(d));
console.log(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), d.getUTCDay(), d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds(), d.getUTCMilliseconds());
const e = new Date(d);
e.setUTCDate(e.getUTCDate() + 1);
console.log(e.toISOString(), e - d);
const overflow = new Date(Date.UTC(2023, 12, 32));
console.log(overflow.toISOString());
console.log(new Date(0).toISOString(), new Date(-1).toISOString(), Date.UTC(1970, 0), Date.UTC(99, 0), Date.UTC(2024));
console.log(new Date(8.64e15).toISOString(), isNaN(new Date(8.64e15 + 1)), new Date(Date.UTC(-1, 0)).toISOString());
console.log(d.toUTCString(), typeof Date.now(), Date.now() > 1.7e12, typeof Date(), new Date(2020, 0) instanceof Date);
