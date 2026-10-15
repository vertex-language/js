# js/value

The engine's primitive layer: symbols, property keys, BigInts, and the conversions between numbers and strings that the language defines exactly (ECMA-262 §6.1, §7.1).

```vertex
import "js/value"
```

## Types

- **`BigInt`** (class): BigInt is ECMAScript's BigInt (§6.1.6.2): an immutable arbitrary-precision integer over math/big.Integer, with the operations the language defines on it.
- **`Symbol`** (class): Symbol is an ECMAScript symbol. Private names (#x) are symbols too, marked private, so they share property storage but never show up in reflection.
- **`PropertyKey`** (enum): PropertyKey is a property's name: an array index, a string, or a symbol.

## Functions

- `func NumberToString(_ x: float64) -> string`: NumberToString is Number::toString(x) in radix 10.
- `func NumberToJSString(_ x: float64) -> str.JSString`: NumberToJSString is NumberToString as a JSString.
- `func NumberToRadixString(_ value: float64, _ radix: int) -> string`: NumberToRadixString is Number.prototype.toString(radix) for radix != 10, after V8's DoubleToRadixCString.
- `func ToFixed(_ x: float64, _ f: int) -> string`: ToFixed is Number.prototype.toFixed for 0 <= f <= 100, x finite and below 1e21 in magnitude.
- `func ToExponential(_ x: float64, _ f: int) -> string`: ToExponential is Number.prototype.toExponential; f < 0 means as many digits as needed (the shortest form).
- `func ToPrecision(_ x: float64, _ p: int) -> string`: ToPrecision is Number.prototype.toPrecision for 1 <= p <= 100.
- `func TrimSpace(_ u: [uint16]) -> [uint16]`: TrimSpace removes leading and trailing WhiteSpace and line terminators.
- `func StringToNumber(_ s: str.JSString) -> float64`: StringToNumber converts a string by the StringNumericLiteral grammar: NaN if it doesn't match.
- `func ParseFloat(_ s: str.JSString) -> float64`: ParseFloat is the global parseFloat: the longest prefix that is a StrDecimalLiteral.
- `func ParseInt(_ s: str.JSString, _ radixIn: int) -> float64`: ParseInt is the global parseInt.
- and 5 more

Part of the [`js`](https://github.com/vertex-language/js) repository.
