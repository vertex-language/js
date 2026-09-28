package token

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

/// Token is a scanned token with position and text.
public struct Token: Equatable {
    public var Kind: TokenKind
    public var Text: string
    public var Pos: int
    public var EndPos: int
    public var HasPrecedingLineBreak: bool

    public init(Kind: TokenKind, Text: string = "", Pos: int = 0, EndPos: int = 0, HasPrecedingLineBreak: bool = false) {
        self.Kind = Kind
        self.Text = Text
        self.Pos = Pos
        self.EndPos = EndPos
        self.HasPrecedingLineBreak = HasPrecedingLineBreak
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
