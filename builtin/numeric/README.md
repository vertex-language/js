# js/builtin/numeric

Installs the numbers and dates (ECMA-262 §21): Number, BigInt, Math and Date.

```vertex
import "js/builtin/numeric"
```

## Types

- **`Zone`** (class): Zone is what Date needs of the local time zone: the offset from UTC in effect at a UTC time, and the zone's name for toString.

## Functions

- `func DateString(_ tv: float64) -> string`: DateString is ToDateString (§21.4.4.41.4): Date.prototype.toString.
- `func ISOString(_ tv: float64) -> string`: ISOString is Date.prototype.toISOString's format.
- `func Parse(_ s: string) -> float64`: Parse is Date.parse: the date time string format (§21.4.1.32), then the forms V8 also accepts -- its own toString and toUTCString output and the common "Month day, year [time]" and "year/month/day" forms.
- `func Install(_ r: object.Realm)`: Install defines Number, BigInt, Math and Date.
- `func LocaleString(_ x: float64) -> string`: LocaleString is toLocaleString in en-US: grouped thousands and at most three fraction digits, as ICU formats it.
- `func Hypot(_ xs: [float64]) -> float64`: Hypot is Math.hypot as V8 computes it: scale by the largest magnitude and sum the squares with Kahan compensation.
- `func SumPrecise(_ xs: [float64]) -> float64`: SumPrecise is Math.sumPrecise (§21.3.2.34): the exact sum rounded once, by Shewchuk's partials.

Part of the [`js`](https://github.com/vertex-language/js) repository.
