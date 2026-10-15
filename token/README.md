# js/token

The JavaScript engine's tokens: token kinds, source positions, operator precedence, keyword lookup, and character classes.

```vertex
import "js/token"
```

## Types

- **`TokenKind`** (enum): TokenKind represents the category of a lexical token in ECMAScript.
- **`Token`** (struct): Token is a scanned token with its position and, for literals, its value.
- **`Position`** (struct): Position represents a source location in line and column coordinates.
- **`SourceFile`** (class): SourceFile records source text and line offset boundaries for fast coordinate resolution.

## Functions

- `func Precedence(_ kind: TokenKind) -> int`: Precedence returns the binary operator precedence (higher binds tighter). Returns 0 for non-binary operators.
- `func LookupKeyword(_ name: string) -> TokenKind?`: LookupKeyword looks up a reserved or contextual keyword by name.
- `func IsWhiteSpace(_ c: uint32) -> bool`: IsWhiteSpace is WhiteSpace (§12.2): TAB, VT, FF, SP, NBSP, ZWNBSP and the Zs category.
- `func IsLineTerminator(_ c: uint32) -> bool`: IsLineTerminator is LineTerminator (§12.3): LF, CR, LS and PS.
- `func IsSpace(_ c: uint32) -> bool`: IsSpace is StrWhiteSpaceChar (§7.1.4.1): WhiteSpace or LineTerminator, what String.prototype.trim removes and \s matches.
- `func IsIdentifierStart(_ c: uint32) -> bool`: IsIdentifierStart is IdentifierStartChar (§12.7): ID_Start, $ or _.
- `func IsIdentifierPart(_ c: uint32) -> bool`: IsIdentifierPart is IdentifierPartChar (§12.7): ID_Continue, $, ZWNJ or ZWJ.
- `func HexValue(_ c: uint32) -> int`: HexValue is a HexDigit's value, or -1.

Part of the [`js`](https://github.com/vertex-language/js) repository.
