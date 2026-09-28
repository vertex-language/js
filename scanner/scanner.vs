package scanner

import "js/token"

/// Scanner tokenizes JavaScript source code.
public final class Scanner {
    public let File: token.SourceFile
    let bytes: [uint8]
    var offset: int = 0
    var hasPrecedingLineBreak: bool = false

    public init(file: token.SourceFile) {
        self.File = file
        self.bytes = [uint8](file.Source.utf8)
    }

    public init(source: string, filename: string = "") {
        let f = token.SourceFile(Filename: filename, Source: source)
        self.File = f
        self.bytes = [uint8](source.utf8)
    }

    /// HasPrecedingLineBreak reports whether a line break was encountered before the last token.
    public var PrecedingLineBreak: bool {
        return hasPrecedingLineBreak
    }

    /// Next returns the next token from the input.
    public func Next() -> token.Token {
        hasPrecedingLineBreak = false
        skipWhitespaceAndComments()

        if offset >= bytes.count {
            return token.Token(Kind: .eof, Text: "", Pos: offset, EndPos: offset, HasPrecedingLineBreak: hasPrecedingLineBreak)
        }

        let startPos = offset
        let lineBreak = hasPrecedingLineBreak
        let b = bytes[offset]

        // Identifiers and keywords
        if isIdentStart(b) {
            return scanIdent(startPos: startPos, lineBreak: lineBreak)
        }

        // Numbers: digits or '.' followed by a digit
        if isDigit(b) || (b == 0x2E && offset + 1 < bytes.count && isDigit(bytes[offset + 1])) {
            return scanNumber(startPos: startPos, lineBreak: lineBreak)
        }

        // Strings
        if b == 0x22 || b == 0x27 { // '"' or '\''
            return scanString(quote: b, startPos: startPos, lineBreak: lineBreak)
        }

        // Template literals
        if b == 0x60 { // '`'
            return scanTemplate(startPos: startPos, lineBreak: lineBreak)
        }

        // Punctuators and operators
        offset += 1
        switch b {
        case 0x28: // (
            return token.Token(Kind: .lParen, Text: "(", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        case 0x29: // )
            return token.Token(Kind: .rParen, Text: ")", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        case 0x7B: // {
            return token.Token(Kind: .lBrace, Text: "{", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        case 0x7D: // }
            return token.Token(Kind: .rBrace, Text: "}", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        case 0x5B: // [
            return token.Token(Kind: .lBracket, Text: "[", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        case 0x5D: // ]
            return token.Token(Kind: .rBracket, Text: "]", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        case 0x3B: // ;
            return token.Token(Kind: .semi, Text: ";", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        case 0x2C: // ,
            return token.Token(Kind: .comma, Text: ",", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        case 0x3A: // :
            return token.Token(Kind: .colon, Text: ":", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        case 0x7E: // ~
            return token.Token(Kind: .bitNot, Text: "~", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        case 0x23: // #
            return token.Token(Kind: .hash, Text: "#", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x2E: // . or ...
            if match(0x2E) {
                if match(0x2E) {
                    return token.Token(Kind: .dotDotDot, Text: "...", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                offset -= 1
            }
            return token.Token(Kind: .dot, Text: ".", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x3F: // ? or ?. or ?? or ??=
            if match(0x2E) {
                return token.Token(Kind: .questionDot, Text: "?.", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if match(0x3F) {
                if match(0x3D) {
                    return token.Token(Kind: .nullishAssign, Text: "??=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .nullishCoalesce, Text: "??", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .question, Text: "?", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x3D: // = or == or === or =>
            if match(0x3D) {
                if match(0x3D) {
                    return token.Token(Kind: .strictEq, Text: "===", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .eq, Text: "==", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if match(0x3E) {
                return token.Token(Kind: .arrow, Text: "=>", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .assign, Text: "=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x21: // ! or != or !==
            if match(0x3D) {
                if match(0x3D) {
                    return token.Token(Kind: .strictNotEq, Text: "!==", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .notEq, Text: "!=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .logicalNot, Text: "!", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x2B: // + or ++ or +=
            if match(0x2B) {
                return token.Token(Kind: .inc, Text: "++", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if match(0x3D) {
                return token.Token(Kind: .addAssign, Text: "+=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .add, Text: "+", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x2D: // - or -- or -=
            if match(0x2D) {
                return token.Token(Kind: .dec, Text: "--", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if match(0x3D) {
                return token.Token(Kind: .subAssign, Text: "-=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .sub, Text: "-", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x2A: // * or ** or *= or **=
            if match(0x2A) {
                if match(0x3D) {
                    return token.Token(Kind: .expAssign, Text: "**=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .exp, Text: "**", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if match(0x3D) {
                return token.Token(Kind: .mulAssign, Text: "*=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .mul, Text: "*", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x2F: // / or /=
            if match(0x3D) {
                return token.Token(Kind: .divAssign, Text: "/=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .div, Text: "/", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x25: // % or %=
            if match(0x3D) {
                return token.Token(Kind: .modAssign, Text: "%=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .mod, Text: "%", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x26: // & or && or &= or &&=
            if match(0x26) {
                if match(0x3D) {
                    return token.Token(Kind: .logicalAndAssign, Text: "&&=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .logicalAnd, Text: "&&", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if match(0x3D) {
                return token.Token(Kind: .andAssign, Text: "&=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .bitAnd, Text: "&", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x7C: // | or || or |= or ||=
            if match(0x7C) {
                if match(0x3D) {
                    return token.Token(Kind: .logicalOrAssign, Text: "||=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .logicalOr, Text: "||", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if match(0x3D) {
                return token.Token(Kind: .orAssign, Text: "|=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .bitOr, Text: "|", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x5E: // ^ or ^=
            if match(0x3D) {
                return token.Token(Kind: .xorAssign, Text: "^=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .bitXor, Text: "^", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x3C: // < or <= or << or <<=
            if match(0x3C) {
                if match(0x3D) {
                    return token.Token(Kind: .shlAssign, Text: "<<=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .shl, Text: "<<", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if match(0x3D) {
                return token.Token(Kind: .lessEq, Text: "<=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .less, Text: "<", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        case 0x3E: // > or >= or >> or >>= or >>> or >>>=
            if match(0x3E) {
                if match(0x3E) {
                    if match(0x3D) {
                        return token.Token(Kind: .ushrAssign, Text: ">>>=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                    }
                    return token.Token(Kind: .ushr, Text: ">>>", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                if match(0x3D) {
                    return token.Token(Kind: .shrAssign, Text: ">>=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .shr, Text: ">>", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if match(0x3D) {
                return token.Token(Kind: .greaterEq, Text: ">=", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            return token.Token(Kind: .greater, Text: ">", Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)

        default:
            return token.Token(Kind: .illegal, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        }
    }

    /// ScanRegExp scans a regular expression literal when the parser determines '/' is not a division.
    public func ScanRegExp(startPos: int, lineBreak: bool = false) -> token.Token {
        var inClass = false
        while offset < bytes.count {
            let b = bytes[offset]
            offset += 1
            if b == 0x5C { // \ (escape)
                if offset < bytes.count { offset += 1 }
                continue
            }
            if b == 0x5B { // [
                inClass = true
            } else if b == 0x5D { // ]
                inClass = false
            } else if b == 0x2F && !inClass { // /
                break
            } else if b == 0x0A || b == 0x0D {
                return token.Token(Kind: .illegal, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
        }
        // Scan flags: g, i, m, s, u, y, v, d
        while offset < bytes.count && isIdentPart(bytes[offset]) {
            offset += 1
        }
        return token.Token(Kind: .regexLiteral, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
    }

    func match(_ expected: uint8) -> bool {
        if offset < bytes.count && bytes[offset] == expected {
            offset += 1
            return true
        }
        return false
    }

    func skipWhitespaceAndComments() {
        while offset < bytes.count {
            let b = bytes[offset]
            if b == 0x20 || b == 0x09 || b == 0x0B || b == 0x0C { // space, tab, vtab, ffeed
                offset += 1
            } else if b == 0x0A { // \n
                offset += 1
                hasPrecedingLineBreak = true
            } else if b == 0x0D { // \r
                offset += 1
                if offset < bytes.count && bytes[offset] == 0x0A {
                    offset += 1
                }
                hasPrecedingLineBreak = true
            } else if b == 0x2F && offset + 1 < bytes.count && bytes[offset + 1] == 0x2F { // //
                offset += 2
                while offset < bytes.count && bytes[offset] != 0x0A && bytes[offset] != 0x0D {
                    offset += 1
                }
            } else if b == 0x2F && offset + 1 < bytes.count && bytes[offset + 1] == 0x2A { // /*
                offset += 2
                while offset + 1 < bytes.count {
                    if bytes[offset] == 0x0A || bytes[offset] == 0x0D {
                        hasPrecedingLineBreak = true
                    }
                    if bytes[offset] == 0x2A && bytes[offset + 1] == 0x2F {
                        offset += 2
                        break
                    }
                    offset += 1
                }
            } else {
                break
            }
        }
    }

    func scanIdent(startPos: int, lineBreak: bool) -> token.Token {
        while offset < bytes.count && isIdentPart(bytes[offset]) {
            offset += 1
        }
        let txt = slice(startPos, offset)
        if let kw = token.LookupKeyword(txt) {
            return token.Token(Kind: kw, Text: txt, Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        }
        return token.Token(Kind: .identifier, Text: txt, Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
    }

    func scanNumber(startPos: int, lineBreak: bool) -> token.Token {
        offset += 1
        if bytes[startPos] == 0x30 && offset < bytes.count { // starts with '0'
            let b = bytes[offset]
            if b == 0x78 || b == 0x58 { // 0x or 0X
                offset += 1
                while offset < bytes.count && (isHexDigit(bytes[offset]) || bytes[offset] == 0x5F) {
                    offset += 1
                }
                if offset < bytes.count && bytes[offset] == 0x6E { // BigInt 'n'
                    offset += 1
                    return token.Token(Kind: .bigint, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .number, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            } else if b == 0x6F || b == 0x4F { // 0o or 0O
                offset += 1
                while offset < bytes.count && (isOctalDigit(bytes[offset]) || bytes[offset] == 0x5F) {
                    offset += 1
                }
                if offset < bytes.count && bytes[offset] == 0x6E {
                    offset += 1
                    return token.Token(Kind: .bigint, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .number, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            } else if b == 0x62 || b == 0x42 { // 0b or 0B
                offset += 1
                while offset < bytes.count && (isBinaryDigit(bytes[offset]) || bytes[offset] == 0x5F) {
                    offset += 1
                }
                if offset < bytes.count && bytes[offset] == 0x6E {
                    offset += 1
                    return token.Token(Kind: .bigint, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
                }
                return token.Token(Kind: .number, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
        }

        while offset < bytes.count && (isDigit(bytes[offset]) || bytes[offset] == 0x5F) {
            offset += 1
        }
        if offset < bytes.count && bytes[offset] == 0x2E { // '.'
            offset += 1
            while offset < bytes.count && (isDigit(bytes[offset]) || bytes[offset] == 0x5F) {
                offset += 1
            }
        }
        if offset < bytes.count && (bytes[offset] == 0x65 || bytes[offset] == 0x45) { // 'e' or 'E'
            offset += 1
            if offset < bytes.count && (bytes[offset] == 0x2B || bytes[offset] == 0x2D) { // '+' or '-'
                offset += 1
            }
            while offset < bytes.count && (isDigit(bytes[offset]) || bytes[offset] == 0x5F) {
                offset += 1
            }
        }
        if offset < bytes.count && bytes[offset] == 0x6E { // BigInt 'n'
            offset += 1
            return token.Token(Kind: .bigint, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
        }
        return token.Token(Kind: .number, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
    }

    func scanString(quote: uint8, startPos: int, lineBreak: bool) -> token.Token {
        offset += 1
        while offset < bytes.count {
            let b = bytes[offset]
            offset += 1
            if b == quote {
                return token.Token(Kind: .string, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if b == 0x5C { // \ escape
                if offset < bytes.count {
                    offset += 1
                }
            } else if b == 0x0A || b == 0x0D {
                return token.Token(Kind: .illegal, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
        }
        return token.Token(Kind: .illegal, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
    }

    func scanTemplate(startPos: int, lineBreak: bool) -> token.Token {
        offset += 1
        while offset < bytes.count {
            let b = bytes[offset]
            offset += 1
            if b == 0x60 { // '`' ends no-substitution template
                return token.Token(Kind: .templateNoSub, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if b == 0x24 && offset < bytes.count && bytes[offset] == 0x7B { // ${
                offset += 1
                return token.Token(Kind: .templateHead, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
            }
            if b == 0x5C { // \ escape
                if offset < bytes.count { offset += 1 }
            }
        }
        return token.Token(Kind: .illegal, Text: slice(startPos, offset), Pos: startPos, EndPos: offset, HasPrecedingLineBreak: lineBreak)
    }

    func slice(_ start: int, _ end: int) -> string {
        if start >= end || start >= bytes.count { return "" }
        let e = end <= bytes.count ? end : bytes.count
        var sub: [uint8] = []
        for i in start..<e {
            sub.append(bytes[i])
        }
        return String(decoding: sub, as: UTF8.self)
    }

    func isIdentStart(_ b: uint8) -> bool {
        return (b >= 0x61 && b <= 0x7A) || // a-z
               (b >= 0x41 && b <= 0x5A) || // A-Z
               b == 0x5F || b == 0x24       // _ or $
    }

    func isIdentPart(_ b: uint8) -> bool {
        return isIdentStart(b) || isDigit(b)
    }

    func isDigit(_ b: uint8) -> bool {
        return b >= 0x30 && b <= 0x39
    }

    func isHexDigit(_ b: uint8) -> bool {
        return isDigit(b) || (b >= 0x61 && b <= 0x66) || (b >= 0x41 && b <= 0x46)
    }

    func isOctalDigit(_ b: uint8) -> bool {
        return b >= 0x30 && b <= 0x37
    }

    func isBinaryDigit(_ b: uint8) -> bool {
        return b == 0x30 || b == 0x31
    }
}
