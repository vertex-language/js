// Package scanner turns ECMAScript source text into tokens (ECMA-262 §12).
//
// The scanner reads on demand. Two tokens depend on what the parser
// expects, so the parser asks for them again: a "/" that starts an
// expression is a regular expression (RescanRegExp), and a "}" that closes
// a template substitution continues the template (RescanTemplate).
package scanner

import (
    "js/token"
    "unicode/utf8"
    "unicode/utf16"
)

/// ScanError is a lexical error at a byte offset.
public enum ScanError: Error {
    case error(message: string, pos: int)
}

/// State is a scanner position that Save returns and Restore goes back to,
/// for the parser's lookahead.
public struct State {
    var pos: int
    var line: int
    var errors: int
}

/// Scanner reads tokens from UTF-8 source.
public final class Scanner {
    public let Source: string
    let src: [uint8]
    var pos: int = 0
    var line: int = 1
    /// Errors collects lexical errors; the parser reports the first one.
    public var Errors: [ScanError] = []

    public init(_ source: string) {
        self.Source = source
        self.src = [uint8](source.utf8)
        // A hashbang comment is allowed only at the very start.
        if src.count >= 2 && src[0] == 0x23 && src[1] == 0x21 {
            while pos < src.count && src[pos] != 0x0A && src[pos] != 0x0D { pos += 1 }
        }
    }

    public var Bytes: [uint8] { return src }

    public func Save() -> State { return State(pos: pos, line: line, errors: Errors.count) }

    public func Restore(_ s: State) {
        pos = s.pos
        line = s.line
        while Errors.count > s.errors { _ = Errors.removeLast() }
    }

    /// Slice is the source text between two byte offsets.
    public func Slice(_ start: int, _ end: int) -> string {
        if start >= end { return "" }
        var b: [uint8] = []
        b.reserveCapacity(end - start)
        var i = start
        while i < end && i < src.count { b.append(src[i]); i += 1 }
        return string(decoding: b, as: UTF8.self)
    }

    func fail(_ msg: string, _ at: int) {
        Errors.append(.error(message: msg, pos: at))
    }

    func peekByte(_ off: int) -> uint8 {
        let i = pos + off
        return i < src.count ? src[i] : 0
    }

    /// Next scans the next token. A "/" is scanned as division; the parser
    /// rescans it where a regular expression may start.
    public func Next() -> token.Token {
        let lineBreak = skipTrivia()
        let start = pos
        var tok = token.Token(Kind: .eof, Pos: start, EndPos: start, HasPrecedingLineBreak: lineBreak)
        tok.Line = line
        if pos >= src.count {
            return tok
        }
        let c = src[pos]

        if c >= 0x80 {
            let (cp, _) = utf8.DecodeAt(src, pos)
            if token.IsIdentifierStart(cp) {
                return scanIdentifier(tok)
            }
            pos += 1
            while pos < src.count && src[pos] >= 0x80 && src[pos] < 0xC0 { pos += 1 }
            fail("Invalid or unexpected token", start)
            tok.Kind = .illegal
            tok.EndPos = pos
            return tok
        }
        if isIdentStartASCII(c) || c == 0x5C {
            return scanIdentifier(tok)
        }
        if c >= 0x30 && c <= 0x39 {
            return scanNumber(tok)
        }
        if c == 0x2E && peekByte(1) >= 0x30 && peekByte(1) <= 0x39 {
            return scanNumber(tok)
        }
        if c == 0x22 || c == 0x27 {
            return scanString(tok, quote: c)
        }
        if c == 0x60 {
            pos += 1
            return scanTemplatePart(tok, head: true)
        }
        if c == 0x23 {
            // #name, a private name.
            pos += 1
            if pos < src.count && (isIdentStartASCII(src[pos]) || src[pos] == 0x5C || src[pos] >= 0x80) {
                var id = scanIdentifier(tok)
                id.Kind = .privateName
                id.Pos = start
                return id
            }
            tok.Kind = .hash
            tok.EndPos = pos
            return tok
        }
        return scanPunctuator(tok)
    }

    // MARK: trivia

    /// skipTrivia skips whitespace and comments, and says whether a line
    /// terminator was among them.
    func skipTrivia() -> bool {
        var lineBreak = false
        while pos < src.count {
            let c = src[pos]
            if c == 0x0A {
                line += 1
                lineBreak = true
                pos += 1
            } else if c == 0x0D {
                line += 1
                lineBreak = true
                pos += 1
                if pos < src.count && src[pos] == 0x0A { pos += 1 }
            } else if c == 0x20 || c == 0x09 || c == 0x0B || c == 0x0C {
                pos += 1
            } else if c == 0x2F && peekByte(1) == 0x2F {
                pos += 2
                skipLineComment()
            } else if c == 0x2F && peekByte(1) == 0x2A {
                let start = pos
                pos += 2
                var closed = false
                while pos < src.count {
                    let d = src[pos]
                    if d == 0x2A && peekByte(1) == 0x2F {
                        pos += 2
                        closed = true
                        break
                    }
                    if d == 0x0A || d == 0x0D {
                        if !(d == 0x0D && peekByte(1) == 0x0A) { line += 1 }
                        lineBreak = true
                        pos += 1
                    } else if d == 0xE2 && peekByte(1) == 0x80 && (peekByte(2) == 0xA8 || peekByte(2) == 0xA9) {
                        line += 1
                        lineBreak = true
                        pos += 3
                    } else {
                        pos += 1
                    }
                }
                if !closed { fail("Invalid or unexpected token", start) }
            } else if c == 0x3C && peekByte(1) == 0x21 && peekByte(2) == 0x2D && peekByte(3) == 0x2D {
                // <!-- is a single-line comment in scripts (Annex B).
                pos += 4
                skipLineComment()
            } else if c == 0x2D && peekByte(1) == 0x2D && peekByte(2) == 0x3E && (lineBreak || pos == 0) {
                // --> at the start of a line is a comment too.
                pos += 3
                skipLineComment()
            } else if c >= 0x80 {
                let (cp, w) = utf8.DecodeAt(src, pos)
                if cp == 0x2028 || cp == 0x2029 {
                    line += 1
                    lineBreak = true
                    pos += w
                } else if token.IsWhiteSpace(cp) {
                    pos += w
                } else {
                    break
                }
            } else {
                break
            }
        }
        return lineBreak
    }

    func skipLineComment() {
        while pos < src.count {
            let c = src[pos]
            if c == 0x0A || c == 0x0D { return }
            if c == 0xE2 && peekByte(1) == 0x80 && (peekByte(2) == 0xA8 || peekByte(2) == 0xA9) { return }
            pos += 1
        }
    }

    // MARK: identifiers

    func isIdentStartASCII(_ c: uint8) -> bool {
        return (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x24 || c == 0x5F
    }

    func isIdentPartASCII(_ c: uint8) -> bool {
        return isIdentStartASCII(c) || (c >= 0x30 && c <= 0x39)
    }

    /// readUnicodeEscape reads \uXXXX or \u{X...} after the backslash's u,
    /// with pos just past the "u". It returns the code point, or -1.
    func readUnicodeEscape() -> int64 {
        if pos < src.count && src[pos] == 0x7B {
            pos += 1
            var v: int64 = 0
            var digits = 0
            while pos < src.count && src[pos] != 0x7D {
                let h = token.HexValue(uint32(src[pos]))
                if h < 0 { return -1 }
                v = v * 16 + int64(h)
                if v > 0x10FFFF { return -1 }
                digits += 1
                pos += 1
            }
            if pos >= src.count || digits == 0 { return -1 }
            pos += 1
            return v
        }
        var v: int64 = 0
        for _ in 0..<4 {
            if pos >= src.count { return -1 }
            let h = token.HexValue(uint32(src[pos]))
            if h < 0 { return -1 }
            v = v * 16 + int64(h)
            pos += 1
        }
        return v
    }

    func scanIdentifier(_ t: token.Token) -> token.Token {
        var tok = t
        let start = pos
        var escaped = false
        var bytes: [uint8] = []
        var first = true
        while pos < src.count {
            let c = src[pos]
            if c < 0x80 {
                if c == 0x5C {
                    let at = pos
                    pos += 1
                    if pos >= src.count || src[pos] != 0x75 {
                        fail("Invalid or unexpected token", at)
                        break
                    }
                    pos += 1
                    let cp = readUnicodeEscape()
                    if cp < 0 || !(first ? token.IsIdentifierStart(uint32(cp)) : token.IsIdentifierPart(uint32(cp))) {
                        fail("Invalid Unicode escape sequence", at)
                        break
                    }
                    utf8.Append(&bytes, uint32(cp))
                    escaped = true
                } else if first ? isIdentStartASCII(c) : isIdentPartASCII(c) {
                    bytes.append(c)
                    pos += 1
                } else {
                    break
                }
            } else {
                let (cp, w) = utf8.DecodeAt(src, pos)
                if !(first ? token.IsIdentifierStart(cp) : token.IsIdentifierPart(cp)) { break }
                var i = 0
                while i < w { bytes.append(src[pos + i]); i += 1 }
                pos += w
            }
            first = false
        }
        let name = string(decoding: bytes, as: UTF8.self)
        tok.Text = name
        tok.Escaped = escaped
        tok.EndPos = pos
        tok.Kind = .identifier
        if let kw = token.LookupKeyword(name) {
            tok.Kind = kw
        }
        _ = start
        return tok
    }

    // MARK: numbers

    func scanNumber(_ t: token.Token) -> token.Token {
        var tok = t
        let start = pos
        tok.Kind = .number
        let c = src[pos]
        if c == 0x30 && pos + 1 < src.count {
            let n = src[pos + 1] | 0x20
            var radix: int = 0
            if n == 0x78 { radix = 16 } else if n == 0x6F { radix = 8 } else if n == 0x62 { radix = 2 }
            if radix != 0 {
                pos += 2
                var v: float64 = 0
                var digits = 0
                var big: [uint8] = []
                var lastSep = true
                while pos < src.count {
                    let d = src[pos]
                    if d == 0x5F {
                        if lastSep { fail("Numeric separators are not allowed here", pos) }
                        lastSep = true
                        pos += 1
                        continue
                    }
                    let h = token.HexValue(uint32(d))
                    if h < 0 || h >= radix { break }
                    v = v * float64(radix) + float64(h)
                    big.append(d)
                    digits += 1
                    lastSep = false
                    pos += 1
                }
                if digits == 0 || lastSep { fail("Invalid or unexpected token", start) }
                if pos < src.count && src[pos] == 0x6E {
                    pos += 1
                    tok.Kind = .bigint
                    let prefix = radix == 16 ? "0x" : (radix == 8 ? "0o" : "0b")
                    tok.Text = prefix + string(decoding: big, as: UTF8.self)
                } else {
                    tok.Text = Slice(start, pos)
                    tok.Number = v
                }
                checkAfterNumber()
                tok.EndPos = pos
                return tok
            }
            // Legacy octal (017) or a decimal with a leading zero (089).
            let d1 = src[pos + 1]
            if d1 >= 0x30 && d1 <= 0x39 {
                pos += 1
                var octal = true
                var i = pos
                while i < src.count && src[i] >= 0x30 && src[i] <= 0x39 {
                    if src[i] >= 0x38 { octal = false }
                    i += 1
                }
                tok.LegacyOctal = true
                if octal {
                    var v: float64 = 0
                    while pos < i { v = v * 8 + float64(src[pos] - 0x30); pos += 1 }
                    tok.Number = v
                    tok.Text = Slice(start, pos)
                    tok.EndPos = pos
                    checkAfterNumber()
                    return tok
                }
                pos = start
            }
        }
        var digits: [uint8] = []
        var isInt = true
        let intStart = pos
        scanDigits(&digits)
        // A literal starting with 0 (0_1, 08_9) takes no separators.
        if src[intStart] == 0x30 && pos - intStart > digits.count {
            fail("Numeric separator can not be used after leading 0.", intStart + 1)
        }
        if pos < src.count && src[pos] == 0x6E {
            pos += 1
            tok.Kind = .bigint
            tok.Text = string(decoding: digits, as: UTF8.self)
            tok.EndPos = pos
            checkAfterNumber()
            return tok
        }
        if pos < src.count && src[pos] == 0x2E {
            isInt = false
            digits.append(0x2E)
            pos += 1
            scanDigits(&digits)
        }
        if pos < src.count && (src[pos] | 0x20) == 0x65 {
            let save = pos
            var e: [uint8] = [0x65]
            pos += 1
            if pos < src.count && (src[pos] == 0x2B || src[pos] == 0x2D) {
                e.append(src[pos])
                pos += 1
            }
            let before = e.count
            scanDigits(&e)
            if e.count == before {
                pos = save
                fail("Invalid or unexpected token", start)
            } else {
                isInt = false
                digits.append(contentsOf: e)
            }
        }
        _ = isInt
        let text = string(decoding: digits, as: UTF8.self)
        tok.Text = text
        tok.Number = parseDecimal(text)
        tok.EndPos = pos
        checkAfterNumber()
        return tok
    }

    func scanDigits(_ out: inout [uint8]) {
        var lastSep = false
        var any = false
        while pos < src.count {
            let d = src[pos]
            if d == 0x5F {
                if !any || lastSep { fail("Numeric separators are not allowed here", pos) }
                lastSep = true
                pos += 1
                continue
            }
            if d < 0x30 || d > 0x39 { break }
            out.append(d)
            any = true
            lastSep = false
            pos += 1
        }
        if lastSep { fail("Numeric separators are not allowed at the end of numeric literals", pos - 1) }
    }

    /// An identifier start or digit right after a number is an error (3in).
    func checkAfterNumber() {
        if pos < src.count {
            let c = src[pos]
            if isIdentStartASCII(c) || c == 0x5C || (c >= 0x30 && c <= 0x39) {
                fail("Invalid or unexpected token", pos)
            }
        }
    }

    // MARK: strings

    /// readEscape reads an escape after the backslash into out. It returns
    /// false for a malformed one. legacy is set for an octal escape or \8 \9.
    func readEscape(_ out: inout [uint16], _ legacy: inout bool, inTemplate: bool) -> bool {
        let c = src[pos]
        pos += 1
        switch c {
        case 0x6E: out.append(0x0A)
        case 0x74: out.append(0x09)
        case 0x72: out.append(0x0D)
        case 0x62: out.append(0x08)
        case 0x66: out.append(0x0C)
        case 0x76: out.append(0x0B)
        case 0x0D:
            line += 1
            if pos < src.count && src[pos] == 0x0A { pos += 1 }
        case 0x0A:
            line += 1
        case 0x78:
            if pos + 1 < src.count {
                let h1 = token.HexValue(uint32(src[pos]))
                let h2 = token.HexValue(uint32(src[pos + 1]))
                if h1 >= 0 && h2 >= 0 {
                    out.append(uint16(h1 * 16 + h2))
                    pos += 2
                    return true
                }
            }
            return false
        case 0x75:
            let cp = readUnicodeEscape()
            if cp < 0 { return false }
            utf16.Append(&out, uint32(cp))
        case 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37:
            let next = pos < src.count ? src[pos] : 0
            if c == 0x30 && !(next >= 0x30 && next <= 0x39) {
                out.append(0)
                return true
            }
            if inTemplate { return false }
            legacy = true
            var v = int(c - 0x30)
            if next >= 0x30 && next <= 0x37 {
                v = v * 8 + int(next - 0x30)
                pos += 1
                let third = pos < src.count ? src[pos] : 0
                if c <= 0x33 && third >= 0x30 && third <= 0x37 {
                    v = v * 8 + int(third - 0x30)
                    pos += 1
                }
            }
            out.append(uint16(v))
        case 0x38, 0x39:
            if inTemplate { return false }
            legacy = true
            out.append(uint16(c))
        default:
            if c >= 0x80 {
                pos -= 1
                let (cp, w) = utf8.DecodeAt(src, pos)
                pos += w
                if cp == 0x2028 || cp == 0x2029 {
                    line += 1
                    return true
                }
                utf16.Append(&out, cp)
            } else {
                out.append(uint16(c))
            }
        }
        return true
    }

    func scanString(_ t: token.Token, quote: uint8) -> token.Token {
        var tok = t
        let start = pos
        pos += 1
        var out: [uint16] = []
        var legacy = false
        var closed = false
        while pos < src.count {
            let c = src[pos]
            if c == quote {
                pos += 1
                closed = true
                break
            }
            if c == 0x0A || c == 0x0D {
                break
            }
            if c == 0x5C {
                pos += 1
                if pos >= src.count { break }
                let at = pos
                if !readEscape(&out, &legacy, inTemplate: false) {
                    fail("Invalid hexadecimal escape sequence", at)
                }
                continue
            }
            if c < 0x80 {
                out.append(uint16(c))
                pos += 1
            } else {
                let (cp, w) = utf8.DecodeAt(src, pos)
                utf16.Append(&out, cp)
                pos += w
            }
        }
        if !closed { fail("Invalid or unexpected token", start) }
        tok.Kind = .string
        tok.Value = out
        tok.LegacyOctal = legacy
        tok.EndPos = pos
        return tok
    }

    // MARK: templates

    /// scanTemplatePart scans from just after ` or } to the next ${ or `.
    func scanTemplatePart(_ t: token.Token, head: bool) -> token.Token {
        var tok = t
        let start = pos
        var cooked: [uint16] = []
        var rawBytes: [uint8] = []
        var invalid = false
        var legacy = false
        var closedBy: int = 0 // 1 for `, 2 for ${
        while pos < src.count {
            let c = src[pos]
            if c == 0x60 {
                pos += 1
                closedBy = 1
                break
            }
            if c == 0x24 && peekByte(1) == 0x7B {
                pos += 2
                closedBy = 2
                break
            }
            if c == 0x5C {
                let escStart = pos
                pos += 1
                if pos >= src.count { break }
                if !readEscape(&cooked, &legacy, inTemplate: true) {
                    invalid = true
                    // Skip what a malformed escape would have consumed.
                    while pos < src.count && src[pos] != 0x60 && src[pos] != 0x5C && !(src[pos] == 0x24 && peekByte(1) == 0x7B) && isIdentPartASCII(src[pos]) {
                        pos += 1
                    }
                }
                // Raw keeps the escape as written, with CRLF and CR as LF.
                var i = escStart
                while i < pos {
                    if src[i] == 0x0D {
                        rawBytes.append(0x0A)
                        if i + 1 < pos && src[i + 1] == 0x0A { i += 1 }
                    } else {
                        rawBytes.append(src[i])
                    }
                    i += 1
                }
                continue
            }
            if c == 0x0D {
                line += 1
                pos += 1
                if pos < src.count && src[pos] == 0x0A { pos += 1 }
                cooked.append(0x0A)
                rawBytes.append(0x0A)
                continue
            }
            if c == 0x0A { line += 1 }
            if c < 0x80 {
                cooked.append(uint16(c))
                rawBytes.append(c)
                pos += 1
            } else {
                let (cp, w) = utf8.DecodeAt(src, pos)
                if cp == 0x2028 || cp == 0x2029 { line += 1 }
                utf16.Append(&cooked, cp)
                var i = 0
                while i < w { rawBytes.append(src[pos + i]); i += 1 }
                pos += w
            }
        }
        if closedBy == 0 { fail("Unterminated template literal", start) }
        if head {
            tok.Kind = closedBy == 2 ? .templateHead : .templateNoSub
        } else {
            tok.Kind = closedBy == 2 ? .templateMiddle : .templateTail
        }
        tok.Value = cooked
        tok.Raw = string(decoding: rawBytes, as: UTF8.self)
        tok.InvalidEscape = invalid
        tok.EndPos = pos
        return tok
    }

    /// RescanTemplate continues a template after a substitution: t is the
    /// "}" token that closed it.
    public func RescanTemplate(_ t: token.Token) -> token.Token {
        pos = t.Pos + 1
        var tok = t
        tok.Text = ""
        return scanTemplatePart(tok, head: false)
    }

    // MARK: regular expressions

    /// RescanRegExp scans a regular expression literal starting at the "/"
    /// or "/=" token t. Text is the pattern, Raw the flags.
    public func RescanRegExp(_ t: token.Token) -> token.Token {
        var tok = t
        pos = t.Pos + 1
        let bodyStart = pos
        var inClass = false
        var closed = false
        while pos < src.count {
            let c = src[pos]
            if c == 0x0A || c == 0x0D { break }
            if c == 0xE2 && peekByte(1) == 0x80 && (peekByte(2) == 0xA8 || peekByte(2) == 0xA9) { break }
            if c == 0x5C {
                pos += 1
                if pos < src.count && src[pos] != 0x0A && src[pos] != 0x0D {
                    pos += 1
                }
                continue
            }
            if c == 0x5B { inClass = true } else if c == 0x5D { inClass = false } else if c == 0x2F && !inClass {
                closed = true
                break
            }
            pos += 1
        }
        if !closed {
            fail("Invalid regular expression: missing /", t.Pos)
            tok.Kind = .illegal
            tok.EndPos = pos
            return tok
        }
        let pattern = Slice(bodyStart, pos)
        pos += 1
        let flagStart = pos
        while pos < src.count && (isIdentPartASCII(src[pos]) || src[pos] == 0x5C) {
            pos += 1
        }
        tok.Kind = .regexLiteral
        tok.Text = pattern
        tok.Raw = Slice(flagStart, pos)
        tok.EndPos = pos
        return tok
    }

    // MARK: punctuators

    func scanPunctuator(_ t: token.Token) -> token.Token {
        var tok = t
        let c = src[pos]
        let c1 = peekByte(1)
        let c2 = peekByte(2)
        let c3 = peekByte(3)
        var kind: token.TokenKind = .illegal
        var n = 1
        switch c {
        case 0x28: kind = .lParen
        case 0x29: kind = .rParen
        case 0x7B: kind = .lBrace
        case 0x7D: kind = .rBrace
        case 0x5B: kind = .lBracket
        case 0x5D: kind = .rBracket
        case 0x3B: kind = .semi
        case 0x2C: kind = .comma
        case 0x3A: kind = .colon
        case 0x7E: kind = .bitNot
        case 0x2E:
            if c1 == 0x2E && c2 == 0x2E { kind = .dotDotDot; n = 3 } else { kind = .dot }
        case 0x3F:
            if c1 == 0x3F {
                if c2 == 0x3D { kind = .nullishAssign; n = 3 } else { kind = .nullishCoalesce; n = 2 }
            } else if c1 == 0x2E && !(c2 >= 0x30 && c2 <= 0x39) {
                kind = .questionDot; n = 2
            } else {
                kind = .question
            }
        case 0x3D:
            if c1 == 0x3D {
                if c2 == 0x3D { kind = .strictEq; n = 3 } else { kind = .eq; n = 2 }
            } else if c1 == 0x3E {
                kind = .arrow; n = 2
            } else {
                kind = .assign
            }
        case 0x21:
            if c1 == 0x3D {
                if c2 == 0x3D { kind = .strictNotEq; n = 3 } else { kind = .notEq; n = 2 }
            } else {
                kind = .logicalNot
            }
        case 0x2B:
            if c1 == 0x2B { kind = .inc; n = 2 } else if c1 == 0x3D { kind = .addAssign; n = 2 } else { kind = .add }
        case 0x2D:
            if c1 == 0x2D { kind = .dec; n = 2 } else if c1 == 0x3D { kind = .subAssign; n = 2 } else { kind = .sub }
        case 0x2A:
            if c1 == 0x2A {
                if c2 == 0x3D { kind = .expAssign; n = 3 } else { kind = .exp; n = 2 }
            } else if c1 == 0x3D {
                kind = .mulAssign; n = 2
            } else {
                kind = .mul
            }
        case 0x2F:
            if c1 == 0x3D { kind = .divAssign; n = 2 } else { kind = .div }
        case 0x25:
            if c1 == 0x3D { kind = .modAssign; n = 2 } else { kind = .mod }
        case 0x26:
            if c1 == 0x26 {
                if c2 == 0x3D { kind = .logicalAndAssign; n = 3 } else { kind = .logicalAnd; n = 2 }
            } else if c1 == 0x3D {
                kind = .andAssign; n = 2
            } else {
                kind = .bitAnd
            }
        case 0x7C:
            if c1 == 0x7C {
                if c2 == 0x3D { kind = .logicalOrAssign; n = 3 } else { kind = .logicalOr; n = 2 }
            } else if c1 == 0x3D {
                kind = .orAssign; n = 2
            } else {
                kind = .bitOr
            }
        case 0x5E:
            if c1 == 0x3D { kind = .xorAssign; n = 2 } else { kind = .bitXor }
        case 0x3C:
            if c1 == 0x3C {
                if c2 == 0x3D { kind = .shlAssign; n = 3 } else { kind = .shl; n = 2 }
            } else if c1 == 0x3D {
                kind = .lessEq; n = 2
            } else {
                kind = .less
            }
        case 0x3E:
            if c1 == 0x3E {
                if c2 == 0x3E {
                    if c3 == 0x3D { kind = .ushrAssign; n = 4 } else { kind = .ushr; n = 3 }
                } else if c2 == 0x3D {
                    kind = .shrAssign; n = 3
                } else {
                    kind = .shr; n = 2
                }
            } else if c1 == 0x3D {
                kind = .greaterEq; n = 2
            } else {
                kind = .greater
            }
        default:
            fail("Invalid or unexpected token", pos)
        }
        tok.Kind = kind
        tok.Text = Slice(pos, pos + n)
        pos += n
        tok.EndPos = pos
        return tok
    }
}

/// parseDecimal converts a decimal literal's digits (no separators) to the
/// nearest double.
public func parseDecimal(_ text: string) -> float64 {
    if let v = float64(text) { return v }
    return float64.nan
}
