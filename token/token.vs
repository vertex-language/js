package token

import "unicode"

/// TokenKind represents the category of a lexical token in ECMAScript.
public enum TokenKind: Equatable {
    case eof
    case illegal

    // Literals and identifiers
    case identifier
    case number
    case bigint
    case string
    case regexLiteral
    case templateHead
    case templateMiddle
    case templateTail
    case templateNoSub

    // Reserved Keywords (ECMA-262 §12.6.2)
    case kAwait
    case kAsync
    case kBreak
    case kCase
    case kCatch
    case kClass
    case kConst
    case kContinue
    case kDebugger
    case kDefault
    case kDelete
    case kDo
    case kElse
    case kExport
    case kExtends
    case kFinally
    case kFor
    case kFunction
    case kIf
    case kImport
    case kIn
    case kInstanceof
    case kLet
    case kNew
    case kReturn
    case kSuper
    case kSwitch
    case kThis
    case kThrow
    case kTry
    case kTypeof
    case kVar
    case kVoid
    case kWhile
    case kWith
    case kYield

    // Literal Keywords
    case kNull
    case kTrue
    case kFalse

    // Contextual Keywords
    case kOf
    case kAs
    case kFrom
    case kGet
    case kSet
    case kTarget
    case kStatic

    // Punctuators
    case lParen          // (
    case rParen          // )
    case lBrace          // {
    case rBrace          // }
    case lBracket        // [
    case rBracket        // ]
    case semi            // ;
    case comma           // ,
    case colon           // :
    case dot             // .
    case dotDotDot       // ...
    case question        // ?
    case questionDot     // ?.
    case arrow           // =>
    case hash            // #
    case privateName     // #name, Text is the name without the #

    // Assignment Operators
    case assign          // =
    case addAssign       // +=
    case subAssign       // -=
    case mulAssign       // *=
    case divAssign       // /=
    case modAssign       // %=
    case expAssign       // **=
    case shlAssign       // <<=
    case shrAssign       // >>=
    case ushrAssign      // >>>=
    case andAssign       // &=
    case orAssign        // |=
    case xorAssign       // ^=
    case logicalAndAssign // &&=
    case logicalOrAssign  // ||=
    case nullishAssign   // ??=

    // Equality
    case eq              // ==
    case notEq           // !=
    case strictEq        // ===
    case strictNotEq     // !==

    // Relational
    case less            // <
    case lessEq          // <=
    case greater         // >
    case greaterEq       // >=

    // Arithmetic and Bitwise
    case add             // +
    case sub             // -
    case mul             // *
    case div             // /
    case mod             // %
    case exp             // **
    case bitAnd          // &
    case bitOr           // |
    case bitXor          // ^
    case bitNot          // ~
    case shl             // <<
    case shr             // >>
    case ushr            // >>>

    // Logical
    case logicalAnd      // &&
    case logicalOr       // ||
    case nullishCoalesce // ??
    case logicalNot      // !

    // Unary update
    case inc             // ++
    case dec             // --
}

/// Token is a scanned token with its position and, for literals, its value.
public struct Token {
    public var Kind: TokenKind
    /// Text is an identifier's or keyword's name (escapes resolved), a
    /// number's or regular expression's source, or a punctuator.
    public var Text: string
    /// Value is a string literal's or template part's cooked UTF-16 value.
    public var Value: [uint16]
    /// Raw is a template part's raw text, or a regular expression's flags.
    public var Raw: string
    public var Number: float64
    public var Pos: int
    public var EndPos: int
    public var Line: int
    public var HasPrecedingLineBreak: bool
    /// Escaped is set when an identifier or keyword was spelled with a
    /// \u escape, which keeps it from being a keyword.
    public var Escaped: bool
    /// InvalidEscape is set on a template part whose cooked value is
    /// undefined (allowed only in tagged templates).
    public var InvalidEscape: bool
    /// LegacyOctal is set on a number like 017 or a string with \07, which
    /// strict mode forbids.
    public var LegacyOctal: bool

    public init(Kind: TokenKind, Text: string = "", Pos: int = 0, EndPos: int = 0, HasPrecedingLineBreak: bool = false) {
        self.Kind = Kind
        self.Text = Text
        self.Value = []
        self.Raw = ""
        self.Number = 0
        self.Pos = Pos
        self.EndPos = EndPos
        self.Line = 1
        self.HasPrecedingLineBreak = HasPrecedingLineBreak
        self.Escaped = false
        self.InvalidEscape = false
        self.LegacyOctal = false
    }

    public var IsAssignment: bool {
        switch Kind {
        case .assign, .addAssign, .subAssign, .mulAssign, .divAssign, .modAssign,
             .expAssign, .shlAssign, .shrAssign, .ushrAssign, .andAssign, .orAssign,
             .xorAssign, .logicalAndAssign, .logicalOrAssign, .nullishAssign:
            return true
        default:
            return false
        }
    }

    public var IsBinaryOperator: bool {
        return Precedence(Kind) > 0
    }

    public var IsIdentifierName: bool {
        switch Kind {
        case .identifier,
             .kAwait, .kAsync, .kBreak, .kCase, .kCatch, .kClass, .kConst, .kContinue,
             .kDebugger, .kDefault, .kDelete, .kDo, .kElse, .kExport, .kExtends, .kFinally,
             .kFor, .kFunction, .kIf, .kImport, .kIn, .kInstanceof, .kLet, .kNew,
             .kReturn, .kSuper, .kSwitch, .kThis, .kThrow, .kTry, .kTypeof, .kVar,
             .kVoid, .kWhile, .kWith, .kYield, .kNull, .kTrue, .kFalse,
             .kOf, .kAs, .kFrom, .kGet, .kSet, .kTarget, .kStatic:
            return true
        default:
            return false
        }
    }

    public var IsContextualKeyword: bool {
        switch Kind {
        case .kOf, .kAs, .kFrom, .kGet, .kSet, .kTarget, .kStatic:
            return true
        default:
            return false
        }
    }
}

/// Precedence returns the binary operator precedence (higher binds tighter).
/// Returns 0 for non-binary operators.
public func Precedence(_ kind: TokenKind) -> int {
    switch kind {
    case .logicalOr:
        return 4
    case .logicalAnd:
        return 5
    case .nullishCoalesce:
        return 5
    case .bitOr:
        return 6
    case .bitXor:
        return 7
    case .bitAnd:
        return 8
    case .eq, .notEq, .strictEq, .strictNotEq:
        return 9
    case .less, .lessEq, .greater, .greaterEq, .kIn, .kInstanceof:
        return 10
    case .shl, .shr, .ushr:
        return 11
    case .add, .sub:
        return 12
    case .mul, .div, .mod:
        return 13
    case .exp:
        return 14
    default:
        return 0
    }
}

/// LookupKeyword looks up a reserved or contextual keyword by name.
public func LookupKeyword(_ name: string) -> TokenKind? {
    switch name {
    case "await": return .kAwait
    case "async": return .kAsync
    case "break": return .kBreak
    case "case": return .kCase
    case "catch": return .kCatch
    case "class": return .kClass
    case "const": return .kConst
    case "continue": return .kContinue
    case "debugger": return .kDebugger
    case "default": return .kDefault
    case "delete": return .kDelete
    case "do": return .kDo
    case "else": return .kElse
    case "export": return .kExport
    case "extends": return .kExtends
    case "finally": return .kFinally
    case "for": return .kFor
    case "function": return .kFunction
    case "if": return .kIf
    case "import": return .kImport
    case "in": return .kIn
    case "instanceof": return .kInstanceof
    case "let": return .kLet
    case "new": return .kNew
    case "return": return .kReturn
    case "super": return .kSuper
    case "switch": return .kSwitch
    case "this": return .kThis
    case "throw": return .kThrow
    case "try": return .kTry
    case "typeof": return .kTypeof
    case "var": return .kVar
    case "void": return .kVoid
    case "while": return .kWhile
    case "with": return .kWith
    case "yield": return .kYield
    case "null": return .kNull
    case "true": return .kTrue
    case "false": return .kFalse
    case "of": return .kOf
    case "as": return .kAs
    case "from": return .kFrom
    case "get": return .kGet
    case "set": return .kSet
    case "target": return .kTarget
    case "static": return .kStatic
    default: return nil
    }
}

/// Position represents a source location in line and column coordinates.
public struct Position: CustomStringConvertible, Equatable {
    public var Filename: string
    public var Line: int
    public var Column: int
    public var Offset: int

    public init(Filename: string = "", Line: int = 1, Column: int = 1, Offset: int = 0) {
        self.Filename = Filename
        self.Line = Line
        self.Column = Column
        self.Offset = Offset
    }

    public var description: string {
        if Filename.isEmpty {
            return "\(Line):\(Column)"
        }
        return "\(Filename):\(Line):\(Column)"
    }
}

/// SourceFile records source text and line offset boundaries for fast coordinate resolution.
public final class SourceFile {
    public let Filename: string
    public let Source: string
    public var LineOffsets: [int]

    public init(Filename: string, Source: string) {
        self.Filename = Filename
        self.Source = Source
        var offsets = [0]
        let bytes = [uint8](Source.utf8)
        for i in 0..<bytes.count {
            if bytes[i] == 0x0A { // \n
                offsets.append(i + 1)
            }
        }
        self.LineOffsets = offsets
    }

    /// PositionAt returns the line and column for a given byte offset.
    public func PositionAt(offset: int) -> Position {
        if offset < 0 {
            return Position(Filename: Filename, Line: 1, Column: 1, Offset: 0)
        }
        var low = 0
        var high = LineOffsets.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if LineOffsets[mid] <= offset {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        let lineIdx = high
        let lineStart = LineOffsets[lineIdx]
        let col = offset - lineStart + 1
        return Position(Filename: Filename, Line: lineIdx + 1, Column: col, Offset: offset)
    }
}

// MARK: lexical character classes (§12.2–§12.7)
//
// ECMAScript's own definitions, which differ from Unicode's properties at
// the edges: WhiteSpace includes U+FEFF and not NEL, and identifiers take
// $, _, ZWNJ and ZWJ besides ID_Start and ID_Continue.

/// IsWhiteSpace is WhiteSpace (§12.2): TAB, VT, FF, SP, NBSP, ZWNBSP and
/// the Zs category.
public func IsWhiteSpace(_ c: uint32) -> bool {
    switch c {
    case 0x09, 0x0B, 0x0C, 0x20, 0xA0, 0xFEFF:
        return true
    default:
        return c >= 0x80 && unicode.Category(c) == .spaceSeparator
    }
}

/// IsLineTerminator is LineTerminator (§12.3): LF, CR, LS and PS.
public func IsLineTerminator(_ c: uint32) -> bool {
    return c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
}

/// IsSpace is StrWhiteSpaceChar (§7.1.4.1): WhiteSpace or LineTerminator,
/// what String.prototype.trim removes and \s matches.
public func IsSpace(_ c: uint32) -> bool {
    return IsWhiteSpace(c) || IsLineTerminator(c)
}

/// IsIdentifierStart is IdentifierStartChar (§12.7): ID_Start, $ or _.
public func IsIdentifierStart(_ c: uint32) -> bool {
    return c == 0x24 || c == 0x5F || unicode.IsIDStart(c)
}

/// IsIdentifierPart is IdentifierPartChar (§12.7): ID_Continue, $, ZWNJ or ZWJ.
public func IsIdentifierPart(_ c: uint32) -> bool {
    return c == 0x24 || c == 0x200C || c == 0x200D || unicode.IsIDContinue(c)
}

/// HexValue is a HexDigit's value, or -1.
public func HexValue(_ c: uint32) -> int {
    if c >= 0x30 && c <= 0x39 { return int(c - 0x30) }
    if c >= 0x61 && c <= 0x66 { return int(c - 0x61 + 10) }
    if c >= 0x41 && c <= 0x46 { return int(c - 0x41 + 10) }
    return -1
}
