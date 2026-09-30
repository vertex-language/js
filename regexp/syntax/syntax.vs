// Package syntax parses ECMAScript regular expressions (ECMA-262 §22.2.1)
// into a tree the js/regexp compiler turns into a program.
//
// The grammar is ES2025's: named groups (duplicates in different
// alternatives), lookbehind, modifiers ((?i:...)), unicode property
// escapes, and the v flag's set notation. Without u or v, the Annex B
// grammar applies, as every browser does: lone ] { } are characters,
// \8 is 8, \12 past the last group is an octal escape, and a lookahead
// may take a quantifier.
//
// Classes are resolved here into sorted code point ranges, so the
// matcher only tests membership.
package syntax

import "unicode"

// MARK: flags

/// Flags are a regular expression's flags.
public struct Flags: Equatable {
    public var HasIndices: bool = false   // d
    public var Global: bool = false       // g
    public var IgnoreCase: bool = false   // i
    public var Multiline: bool = false    // m
    public var DotAll: bool = false       // s
    public var Unicode: bool = false      // u
    public var UnicodeSets: bool = false  // v
    public var Sticky: bool = false       // y

    public init() {}

    /// UnicodeMode is set by u or v: the pattern and the input are code
    /// points, and the Annex B grammar is off.
    public var UnicodeMode: bool { return Unicode || UnicodeSets }
}

/// ParseFlags reads flag characters; nil when one is unknown, repeated,
/// or u and v are both given.
public func ParseFlags(_ f: [uint16]) -> Flags? {
    var fl = Flags()
    for c in f {
        switch c {
        case 0x64: if fl.HasIndices { return nil }; fl.HasIndices = true
        case 0x67: if fl.Global { return nil }; fl.Global = true
        case 0x69: if fl.IgnoreCase { return nil }; fl.IgnoreCase = true
        case 0x6D: if fl.Multiline { return nil }; fl.Multiline = true
        case 0x73: if fl.DotAll { return nil }; fl.DotAll = true
        case 0x75: if fl.Unicode { return nil }; fl.Unicode = true
        case 0x76: if fl.UnicodeSets { return nil }; fl.UnicodeSets = true
        case 0x79: if fl.Sticky { return nil }; fl.Sticky = true
        default: return nil
        }
    }
    if fl.Unicode && fl.UnicodeSets { return nil }
    return fl
}

// MARK: sets

/// MaxCodePoint is the last code point.
public let MaxCodePoint: uint32 = 0x10FFFF

/// CharSet is a class: code points as sorted, merged ranges, flat
/// [first, last, first, last, ...], and, under the v flag, strings of
/// other than one code point (\q{abc}, \p{RGI_Emoji}).
public final class CharSet {
    public var Ranges: [uint32]
    public var Strings: [[uint32]]

    public init(ranges: [uint32] = [], strings: [[uint32]] = []) {
        self.Ranges = ranges
        self.Strings = strings
    }

    public func Contains(_ cp: uint32) -> bool {
        var lo = 0
        var hi = Ranges.count / 2 - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if cp < Ranges[mid * 2] {
                hi = mid - 1
            } else if cp > Ranges[mid * 2 + 1] {
                lo = mid + 1
            } else {
                return true
            }
        }
        return false
    }

    func copy() -> CharSet {
        return CharSet(ranges: Ranges, strings: Strings)
    }

    func addRange(_ lo: uint32, _ hi: uint32) {
        Ranges = unionRanges(Ranges, [lo, hi])
    }

    func add(_ cp: uint32) { addRange(cp, cp) }

    func addSet(_ o: CharSet) {
        Ranges = unionRanges(Ranges, o.Ranges)
        for s in o.Strings where !containsString(Strings, s) { Strings.append(s) }
    }

    func addString(_ s: [uint32]) {
        if s.count == 1 {
            add(s[0])
        } else if !containsString(Strings, s) {
            Strings.append(s)
        }
    }
}

func containsString(_ list: [[uint32]], _ s: [uint32]) -> bool {
    for x in list where x == s { return true }
    return false
}

/// normalize sorts and merges flat ranges.
func normalize(_ r: [uint32]) -> [uint32] {
    var pairs: [(uint32, uint32)] = []
    var i = 0
    while i + 1 < r.count {
        pairs.append((r[i], r[i + 1]))
        i += 2
    }
    pairs.sort(by: { $0.0 < $1.0 })
    var out: [uint32] = []
    for p in pairs {
        if !out.isEmpty && p.0 <= out[out.count - 1] + 1 {
            if p.1 > out[out.count - 1] { out[out.count - 1] = p.1 }
        } else {
            out.append(p.0)
            out.append(p.1)
        }
    }
    return out
}

func unionRanges(_ a: [uint32], _ b: [uint32]) -> [uint32] {
    if b.isEmpty { return a }
    if a.isEmpty { return normalize(b) }
    return normalize(a + b)
}

func complementRanges(_ a: [uint32]) -> [uint32] {
    var out: [uint32] = []
    var next: uint32 = 0
    var i = 0
    while i + 1 < a.count {
        if a[i] > next {
            out.append(next)
            out.append(a[i] - 1)
        }
        next = a[i + 1] + 1
        i += 2
    }
    if next <= MaxCodePoint {
        out.append(next)
        out.append(MaxCodePoint)
    }
    return out
}

func intersectRanges(_ a: [uint32], _ b: [uint32]) -> [uint32] {
    var out: [uint32] = []
    var i = 0
    var j = 0
    while i + 1 < a.count && j + 1 < b.count {
        let lo = a[i] > b[j] ? a[i] : b[j]
        let hi = a[i + 1] < b[j + 1] ? a[i + 1] : b[j + 1]
        if lo <= hi {
            out.append(lo)
            out.append(hi)
        }
        if a[i + 1] < b[j + 1] { i += 2 } else { j += 2 }
    }
    return out
}

func subtractRanges(_ a: [uint32], _ b: [uint32]) -> [uint32] {
    return intersectRanges(a, complementRanges(b))
}

let digitRanges: [uint32] = [0x30, 0x39]
let wordRanges: [uint32] = [0x30, 0x39, 0x41, 0x5A, 0x5F, 0x5F, 0x61, 0x7A]
/// spaceRanges is WhiteSpace and LineTerminator (§12.2, §12.3).
let spaceRanges: [uint32] = [
    0x09, 0x0D, 0x20, 0x20, 0xA0, 0xA0, 0x1680, 0x1680, 0x2000, 0x200A,
    0x2028, 0x2029, 0x202F, 0x202F, 0x205F, 0x205F, 0x3000, 0x3000, 0xFEFF, 0xFEFF,
]

// MARK: the tree

/// NodeKind is what a node matches.
public enum NodeKind {
    case empty
    case char(uint32)
    case dot
    case set(CharSet, bool)            // the class, and whether it is negated
    case lineStart
    case lineEnd
    case wordBoundary(bool)            // negated (\B)
    case seq([Node])
    case alt([Node])
    case group(Node, int)              // a capture and its index (from 1)
    case look(Node, bool, bool)        // ahead, negated
    case repeatNode(Node, int, int, bool)  // min, max (-1: no limit), greedy
    case backref                       // Node.Groups: the groups (several for a duplicated name)
}

/// Node is one part of a pattern, with the modifiers in force where it
/// appears (i, m and s may change inside (?ims-ims:...)).
public final class Node {
    public let Kind: NodeKind
    public var IgnoreCase: bool = false
    public var Multiline: bool = false
    public var DotAll: bool = false
    /// FirstGroup and LastGroup are the captures inside a repeat, which
    /// each iteration resets (0 and -1 when there are none).
    public var FirstGroup: int = 0
    public var LastGroup: int = -1
    /// Groups are a backreference's groups.
    public var Groups: [int] = []

    public init(_ kind: NodeKind) {
        self.Kind = kind
    }
}

/// Pattern is a parsed regular expression.
public final class Pattern {
    public let Root: Node
    public let Flags: Flags
    /// GroupCount is the number of capturing groups.
    public let GroupCount: int
    /// GroupNames is each group's name as UTF-16 (index 0 unused, empty
    /// when unnamed).
    public let GroupNames: [[uint16]]

    public init(root: Node, flags: Flags, groupCount: int, groupNames: [[uint16]]) {
        self.Root = root
        self.Flags = flags
        self.GroupCount = groupCount
        self.GroupNames = groupNames
    }

    /// HasNamedGroups says some group has a name.
    public var HasNamedGroups: bool {
        for n in GroupNames where !n.isEmpty { return true }
        return false
    }
}

/// SyntaxError is an invalid pattern.
public struct SyntaxError: Error, CustomStringConvertible {
    public let Message: string
    public init(_ m: string) { self.Message = m }
    public var description: string { return Message }
}

/// Parse parses a pattern's source (UTF-16) under flags.
public func Parse(_ source: [uint16], _ flags: Flags) throws -> Pattern {
    let p = Parser(source, flags)
    return try p.parse()
}

// MARK: the parser

struct NamedGroup {
    var name: [uint16]
    var index: int
    var path: [int]
}

final class Parser {
    var src: [uint32] = []
    var pos: int = 0
    let flags: Flags
    let umode: bool
    let vmode: bool
    var ic: bool
    var ml: bool
    var da: bool
    var groupCount = 0
    var totalGroups = 0
    var hasNamed = false
    var named: [NamedGroup] = []
    var path: [int] = []
    var disjunctions = 0
    var nameRefs: [(name: [uint16], node: Node)] = []
    var maxBackref = 0

    init(_ source: [uint16], _ f: Flags) {
        flags = f
        umode = f.UnicodeMode
        vmode = f.UnicodeSets
        ic = f.IgnoreCase
        ml = f.Multiline
        da = f.DotAll
        // In unicode mode the pattern is code points; otherwise units.
        var i = 0
        while i < source.count {
            let c = uint32(source[i])
            if umode && c >= 0xD800 && c <= 0xDBFF && i + 1 < source.count {
                let d = uint32(source[i + 1])
                if d >= 0xDC00 && d <= 0xDFFF {
                    src.append(0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00))
                    i += 2
                    continue
                }
            }
            src.append(c)
            i += 1
        }
    }

    func fail(_ msg: string) -> SyntaxError {
        return SyntaxError(msg)
    }

    var atEnd: bool { return pos >= src.count }

    func peek(_ k: int = 0) -> uint32 {
        let i = pos + k
        return i < src.count ? src[i] : 0xFFFFFFFF
    }

    func eat(_ c: uint32) -> bool {
        if pos < src.count && src[pos] == c {
            pos += 1
            return true
        }
        return false
    }

    func node(_ k: NodeKind) -> Node {
        let n = Node(k)
        n.IgnoreCase = ic
        n.Multiline = ml
        n.DotAll = da
        return n
    }

    func parse() throws -> Pattern {
        prescan()
        let root = try parseDisjunction()
        if !atEnd {
            if peek() == 0x29 { throw fail("Unmatched ')'") }
            throw fail("Unexpected character")
        }
        if umode && maxBackref > groupCount { throw fail("Invalid escape") }
        var names: [[uint16]] = []
        var gi = 0
        while gi <= groupCount {
            names.append([])
            gi += 1
        }
        for g in named { names[g.index] = g.name }
        for ref in nameRefs {
            var idx: [int] = []
            for g in named where g.name == ref.name { idx.append(g.index) }
            if idx.isEmpty { throw fail("Invalid named capture referenced") }
            ref.node.Groups = idx
        }
        return Pattern(root: root, flags: flags, groupCount: groupCount, groupNames: names)
    }

    /// prescan counts the capturing groups and finds named ones, which
    /// decide how \N and \k parse before the groups are reached.
    func prescan() {
        var i = 0
        var classDepth = 0
        while i < src.count {
            let c = src[i]
            if c == 0x5C {
                i += 2
                continue
            }
            if classDepth > 0 {
                if c == 0x5D { classDepth -= 1 } else if c == 0x5B && vmode { classDepth += 1 }
                i += 1
                continue
            }
            if c == 0x5B {
                classDepth = 1
            } else if c == 0x28 {
                if i + 1 < src.count && src[i + 1] == 0x3F {
                    if i + 2 < src.count && src[i + 2] == 0x3C && i + 3 < src.count && src[i + 3] != 0x3D && src[i + 3] != 0x21 {
                        totalGroups += 1
                        hasNamed = true
                    }
                } else {
                    totalGroups += 1
                }
            }
            i += 1
        }
    }

    // MARK: disjunctions and terms

    func parseDisjunction() throws -> Node {
        let id = disjunctions
        disjunctions += 1
        var alts: [Node] = []
        var k = 0
        while true {
            path.append(id)
            path.append(k)
            alts.append(try parseAlternative())
            path.removeLast(2)
            k += 1
            if !eat(0x7C) { break }
        }
        return alts.count == 1 ? alts[0] : node(.alt(alts))
    }

    func parseAlternative() throws -> Node {
        var terms: [Node] = []
        while !atEnd && peek() != 0x7C && peek() != 0x29 {
            try parseTerm(&terms)
        }
        if terms.isEmpty { return node(.empty) }
        return terms.count == 1 ? terms[0] : node(.seq(terms))
    }

    func parseTerm(_ terms: inout [Node]) throws {
        let c = peek()
        if c == 0x5E {
            pos += 1
            terms.append(node(.lineStart))
            return
        }
        if c == 0x24 {
            pos += 1
            terms.append(node(.lineEnd))
            return
        }
        if c == 0x5C && (peek(1) == 0x62 || peek(1) == 0x42) {
            pos += 2
            terms.append(node(.wordBoundary(src[pos - 1] == 0x42)))
            return
        }
        if c == 0x28 && peek(1) == 0x3F {
            let d = peek(2)
            var ahead = true
            var negate = false
            var isLook = false
            var skip = 0
            if d == 0x3D || d == 0x21 {
                isLook = true
                negate = d == 0x21
                skip = 3
            } else if d == 0x3C && (peek(3) == 0x3D || peek(3) == 0x21) {
                isLook = true
                ahead = false
                negate = peek(3) == 0x21
                skip = 4
            }
            if isLook {
                pos += skip
                let groupsBefore = groupCount
                let body = try parseDisjunction()
                if !eat(0x29) { throw fail("Unterminated group") }
                let n = node(.look(body, ahead, negate))
                // Annex B: a lookahead may be quantified without u or v.
                if ahead && !umode, let q = try parseQuantifier(n, groupsBefore) {
                    terms.append(q)
                } else {
                    if isQuantifierStart() { throw fail("Invalid quantifier") }
                    terms.append(n)
                }
                return
            }
        }
        let groupsBefore = groupCount
        let atom = try parseAtom()
        if let q = try parseQuantifier(atom, groupsBefore) {
            terms.append(q)
        } else {
            terms.append(atom)
        }
    }

    func isQuantifierStart() -> bool {
        let c = peek()
        if c == 0x2A || c == 0x2B || c == 0x3F { return true }
        if c == 0x7B {
            let save = pos
            let ok = parseBraces() != nil
            pos = save
            return ok || umode
        }
        return false
    }

    /// parseBraces reads {n}, {n,} or {n,m}; nil if it is not one.
    func parseBraces() -> (int, int)? {
        let save = pos
        if !eat(0x7B) { return nil }
        guard let lo = readDecimal() else {
            pos = save
            return nil
        }
        var hi = lo
        if eat(0x2C) {
            if let h = readDecimal() { hi = h } else { hi = -1 }
        }
        if !eat(0x7D) {
            pos = save
            return nil
        }
        return (lo, hi)
    }

    /// readDecimal reads digits, saturating (a huge count is no limit).
    func readDecimal() -> int? {
        var v = 0
        var any = false
        while !atEnd && peek() >= 0x30 && peek() <= 0x39 {
            if v < 1_000_000_000 { v = v * 10 + int(peek() - 0x30) }
            pos += 1
            any = true
        }
        return any ? v : nil
    }

    func parseQuantifier(_ atom: Node, _ groupsBefore: int) throws -> Node? {
        var lo = 0
        var hi = -1
        let c = peek()
        if c == 0x2A {
            pos += 1
        } else if c == 0x2B {
            pos += 1
            lo = 1
        } else if c == 0x3F {
            pos += 1
            hi = 1
        } else if c == 0x7B {
            guard let (a, b) = parseBraces() else {
                if umode { throw fail("Incomplete quantifier") }
                return nil
            }
            lo = a
            hi = b
            if hi >= 0 && lo > hi { throw fail("numbers out of order in {} quantifier") }
        } else {
            return nil
        }
        let greedy = !eat(0x3F)
        let n = node(.repeatNode(atom, lo, hi, greedy))
        if groupCount > groupsBefore {
            n.FirstGroup = groupsBefore + 1
            n.LastGroup = groupCount
        }
        return n
    }

    // MARK: atoms

    func parseAtom() throws -> Node {
        let c = peek()
        switch c {
        case 0x2E:
            pos += 1
            return node(.dot)
        case 0x28:
            return try parseGroup()
        case 0x5B:
            pos += 1
            return try parseClass()
        case 0x5C:
            pos += 1
            return try parseAtomEscape()
        case 0x2A, 0x2B, 0x3F:
            throw fail("Nothing to repeat")
        case 0x7B:
            if umode { throw fail("Nothing to repeat") }
            if parseBraces() != nil { throw fail("Nothing to repeat") }
            pos += 1
            return node(.char(c))
        case 0x7D, 0x5D:
            if umode { throw fail("Lone quantifier brackets") }
            pos += 1
            return node(.char(c))
        default:
            pos += 1
            return node(.char(c))
        }
    }

    func parseGroup() throws -> Node {
        pos += 1
        if eat(0x3F) {
            if eat(0x3A) {
                let body = try parseDisjunction()
                if !eat(0x29) { throw fail("Unterminated group") }
                return body
            }
            if peek() == 0x3C {
                pos += 1
                let name = try parseGroupName()
                groupCount += 1
                let index = groupCount
                for g in named where g.name == name {
                    if !differentAlternatives(g.path, path) { throw fail("Duplicate capture group name") }
                }
                named.append(NamedGroup(name: name, index: index, path: path))
                let body = try parseDisjunction()
                if !eat(0x29) { throw fail("Unterminated group") }
                return node(.group(body, index))
            }
            return try parseModifiers()
        }
        groupCount += 1
        let index = groupCount
        let body = try parseDisjunction()
        if !eat(0x29) { throw fail("Unterminated group") }
        return node(.group(body, index))
    }

    /// differentAlternatives says two alternation paths part at some
    /// disjunction: the groups can never both participate.
    func differentAlternatives(_ a: [int], _ b: [int]) -> bool {
        var i = 0
        while i + 1 < a.count && i + 1 < b.count {
            if a[i] != b[i] { return false }
            if a[i + 1] != b[i + 1] { return true }
            i += 2
        }
        return false
    }

    /// parseModifiers reads (?ims-ims: ... ) (ES2025).
    func parseModifiers() throws -> Node {
        var add: [uint32] = []
        var remove: [uint32] = []
        var removing = false
        while !atEnd && peek() != 0x3A {
            let c = peek()
            if c == 0x2D && !removing {
                removing = true
                pos += 1
                continue
            }
            if c != 0x69 && c != 0x6D && c != 0x73 { throw fail("Invalid group") }
            if add.contains(c) || remove.contains(c) { throw fail("Repeated flag in modifiers") }
            if removing { remove.append(c) } else { add.append(c) }
            pos += 1
        }
        if !eat(0x3A) { throw fail("Invalid group") }
        if removing && add.isEmpty && remove.isEmpty { throw fail("Invalid group") }
        let saved = (ic, ml, da)
        for c in add {
            if c == 0x69 { ic = true } else if c == 0x6D { ml = true } else { da = true }
        }
        for c in remove {
            if c == 0x69 { ic = false } else if c == 0x6D { ml = false } else { da = false }
        }
        let body = try parseDisjunction()
        (ic, ml, da) = saved
        if !eat(0x29) { throw fail("Unterminated group") }
        return body
    }

    /// parseGroupName reads a RegExpIdentifierName and the closing >.
    /// Names are code points whatever the flags.
    func parseGroupName() throws -> [uint16] {
        var cps: [uint32] = []
        while true {
            if atEnd { throw fail("Invalid capture group name") }
            var c = peek()
            if c == 0x3E {
                pos += 1
                break
            }
            if c == 0x5C {
                pos += 1
                if !eat(0x75) { throw fail("Invalid capture group name") }
                guard let v = readUnicodeEscapeInName() else { throw fail("Invalid Unicode escape") }
                c = v
            } else {
                pos += 1
                if c >= 0xD800 && c <= 0xDBFF && !atEnd && peek() >= 0xDC00 && peek() <= 0xDFFF {
                    c = 0x10000 + ((c - 0xD800) << 10) + (peek() - 0xDC00)
                    pos += 1
                }
            }
            let ok = cps.isEmpty
                ? (c == 0x24 || c == 0x5F || unicode.IsIDStart(c))
                : (c == 0x24 || c == 0x5F || c == 0x200C || c == 0x200D || unicode.IsIDContinue(c))
            if !ok { throw fail("Invalid capture group name") }
            cps.append(c)
        }
        if cps.isEmpty { throw fail("Invalid capture group name") }
        return toUnits(cps)
    }

    /// readUnicodeEscapeInName reads after \u in a group name: XXXX, a
    /// surrogate pair of two \u escapes, or {X...}.
    func readUnicodeEscapeInName() -> uint32? {
        if eat(0x7B) {
            var v: uint32 = 0
            var any = false
            while !atEnd && hexValue(peek()) >= 0 {
                v = v * 16 + uint32(hexValue(peek()))
                if v > MaxCodePoint { return nil }
                pos += 1
                any = true
            }
            if !any || !eat(0x7D) { return nil }
            return v
        }
        guard let lead = readHex(4) else { return nil }
        if lead >= 0xD800 && lead <= 0xDBFF && peek() == 0x5C && peek(1) == 0x75 {
            let save = pos
            pos += 2
            if let trail = readHex(4), trail >= 0xDC00 && trail <= 0xDFFF {
                return 0x10000 + ((lead - 0xD800) << 10) + (trail - 0xDC00)
            }
            pos = save
        }
        return lead
    }

    func readHex(_ n: int) -> uint32? {
        var v: uint32 = 0
        var i = 0
        while i < n {
            let h = hexValue(peek(i))
            if h < 0 { return nil }
            v = v * 16 + uint32(h)
            i += 1
        }
        pos += n
        return v
    }

    // MARK: escapes

    func parseAtomEscape() throws -> Node {
        if atEnd { throw fail("\\ at end of pattern") }
        let c = peek()
        if c >= 0x31 && c <= 0x39 {
            let save = pos
            let n = readDecimal()!
            if umode || n <= totalGroups {
                if n > maxBackref { maxBackref = n }
                let b = node(.backref)
                b.Groups = [n]
                return b
            }
            pos = save
            if c >= 0x38 {
                pos += 1
                return node(.char(c))
            }
            return node(.char(readLegacyOctal()))
        }
        if c == 0x6B && (umode || hasNamed) {
            pos += 1
            if !eat(0x3C) { throw fail("Invalid named reference") }
            let name = try parseGroupName()
            let n = node(.backref)
            nameRefs.append((name: name, node: n))
            return n
        }
        if let s = try classEscape() {
            return node(.set(s, false))
        }
        return node(.char(try characterEscape(inClass: false)))
    }

    /// readLegacyOctal reads up to three octal digits (Annex B), at most \377.
    func readLegacyOctal() -> uint32 {
        var v: uint32 = 0
        var n = 0
        while n < 3 && !atEnd && peek() >= 0x30 && peek() <= 0x37 {
            let next = v * 8 + (peek() - 0x30)
            if next > 0o377 { break }
            v = next
            pos += 1
            n += 1
        }
        return v
    }

    /// classEscape reads \d \D \s \S \w \W and, in unicode mode, \p{...}
    /// and \P{...}; nil (nothing consumed) for any other escape.
    func classEscape() throws -> CharSet? {
        let c = peek()
        switch c {
        case 0x64:
            pos += 1
            return CharSet(ranges: digitRanges)
        case 0x44:
            pos += 1
            return CharSet(ranges: complementRanges(digitRanges))
        case 0x73:
            pos += 1
            return CharSet(ranges: spaceRanges)
        case 0x53:
            pos += 1
            return CharSet(ranges: complementRanges(spaceRanges))
        case 0x77:
            pos += 1
            return CharSet(ranges: wordRanges)
        case 0x57:
            pos += 1
            return CharSet(ranges: complementRanges(wordRanges))
        case 0x70, 0x50:
            if !umode { return nil }
            pos += 1
            return try parseProperty(negated: c == 0x50)
        default:
            return nil
        }
    }

    /// characterEscape reads a CharacterEscape (or, in a class, a
    /// ClassEscape that is one character) after the backslash.
    func characterEscape(inClass: bool) throws -> uint32 {
        let c = peek()
        pos += 1
        switch c {
        case 0x66: return 0x0C
        case 0x6E: return 0x0A
        case 0x72: return 0x0D
        case 0x74: return 0x09
        case 0x76: return 0x0B
        case 0x63:
            let l = peek()
            if (l >= 0x41 && l <= 0x5A) || (l >= 0x61 && l <= 0x7A) {
                pos += 1
                return l % 32
            }
            if inClass && !umode && ((l >= 0x30 && l <= 0x39) || l == 0x5F) {
                pos += 1
                return l % 32
            }
            if umode { throw fail("Invalid unicode escape") }
            // Annex B: \c is a backslash, and the c is read again.
            pos -= 1
            return 0x5C
        case 0x30:
            if peek() >= 0x30 && peek() <= 0x39 {
                if umode { throw fail("Invalid decimal escape") }
                pos -= 1
                return readLegacyOctal()
            }
            return 0
        case 0x78:
            if let v = readHex(2) { return v }
            if umode { throw fail("Invalid escape") }
            return 0x78
        case 0x75:
            if let v = readUnicodeEscape() { return v }
            if umode { throw fail("Invalid Unicode escape") }
            return 0x75
        default:
            if umode {
                if isSyntaxCharacter(c) || c == 0x2F { return c }
                if inClass && c == 0x2D { return c }
                if inClass && vmode && isClassSetReservedPunctuator(c) { return c }
                throw fail("Invalid escape")
            }
            if inClass && c >= 0x31 && c <= 0x39 {
                if c >= 0x38 { return c }
                pos -= 1
                return readLegacyOctal()
            }
            if c == 0xFFFFFFFF { throw fail("\\ at end of pattern") }
            return c
        }
    }

    /// readUnicodeEscape reads after \u: XXXX, with a following \uXXXX
    /// trail surrogate joined in unicode mode, or {X...} in unicode mode.
    func readUnicodeEscape() -> uint32? {
        if umode && peek() == 0x7B {
            let save = pos
            pos += 1
            var v: uint32 = 0
            var any = false
            while !atEnd && hexValue(peek()) >= 0 {
                v = v * 16 + uint32(hexValue(peek()))
                if v > MaxCodePoint {
                    pos = save
                    return nil
                }
                pos += 1
                any = true
            }
            if !any || !eat(0x7D) {
                pos = save
                return nil
            }
            return v
        }
        guard let lead = readHex(4) else { return nil }
        if umode && lead >= 0xD800 && lead <= 0xDBFF && peek() == 0x5C && peek(1) == 0x75 {
            let save = pos
            pos += 2
            if let trail = readHex(4), trail >= 0xDC00 && trail <= 0xDFFF {
                return 0x10000 + ((lead - 0xD800) << 10) + (trail - 0xDC00)
            }
            pos = save
        }
        return lead
    }

    // MARK: classes

    func parseClass() throws -> Node {
        let negate = eat(0x5E)
        if vmode {
            let s = try parseClassSetExpression()
            if !eat(0x5D) { throw fail("Unterminated character class") }
            if negate {
                if !s.Strings.isEmpty { throw fail("Negated character class may contain strings") }
                return node(.set(CharSet(ranges: complementRanges(s.Ranges)), false))
            }
            return node(.set(s, false))
        }
        let set = CharSet()
        while true {
            if atEnd { throw fail("Unterminated character class") }
            if eat(0x5D) { break }
            let a = try classAtom()
            if peek() == 0x2D && peek(1) != 0x5D && pos + 1 < src.count {
                pos += 1
                let b = try classAtom()
                switch (a, b) {
                case (.char(let x), .char(let y)):
                    if x > y { throw fail("Range out of order in character class") }
                    set.addRange(x, y)
                default:
                    if umode { throw fail("Invalid character class") }
                    addAtom(set, a)
                    set.add(0x2D)
                    addAtom(set, b)
                }
            } else {
                addAtom(set, a)
            }
        }
        return node(.set(set, negate))
    }

    enum ClassAtom {
        case char(uint32)
        case set(CharSet)
    }

    func addAtom(_ s: CharSet, _ a: ClassAtom) {
        switch a {
        case .char(let c): s.add(c)
        case .set(let o): s.addSet(o)
        }
    }

    func classAtom() throws -> ClassAtom {
        let c = peek()
        pos += 1
        if c != 0x5C { return .char(c) }
        if atEnd { throw fail("\\ at end of pattern") }
        if peek() == 0x62 {
            pos += 1
            return .char(0x08)
        }
        if umode && peek() == 0x2D {
            pos += 1
            return .char(0x2D)
        }
        if let s = try classEscape() { return .set(s) }
        return .char(try characterEscape(inClass: true))
    }

    // MARK: v-mode set notation

    /// parseClassSetExpression reads a ClassSetExpression (after [ and ^):
    /// a union, or operands joined all by && or all by --.
    func parseClassSetExpression() throws -> CharSet {
        if peek() == 0x5D { return CharSet() }
        let first = try parseClassSetOperand(allowRange: true)
        if peek() == 0x26 && peek(1) == 0x26 {
            var acc = first
            while peek() == 0x26 && peek(1) == 0x26 {
                pos += 2
                if peek() == 0x26 { throw fail("Invalid set operation in character class") }
                let rhs = try parseClassSetOperand(allowRange: false)
                acc = intersectSets(acc, rhs)
            }
            if peek() != 0x5D { throw fail("Invalid set operation in character class") }
            return acc
        }
        if peek() == 0x2D && peek(1) == 0x2D {
            var acc = first
            while peek() == 0x2D && peek(1) == 0x2D {
                pos += 2
                let rhs = try parseClassSetOperand(allowRange: false)
                acc = subtractSets(acc, rhs)
            }
            if peek() != 0x5D { throw fail("Invalid set operation in character class") }
            return acc
        }
        let acc = first
        while !atEnd && peek() != 0x5D {
            if (peek() == 0x26 && peek(1) == 0x26) || (peek() == 0x2D && peek(1) == 0x2D) {
                throw fail("Invalid set operation in character class")
            }
            acc.addSet(try parseClassSetOperand(allowRange: true))
        }
        return acc
    }

    func intersectSets(_ a: CharSet, _ b: CharSet) -> CharSet {
        let r = CharSet(ranges: intersectRanges(a.Ranges, b.Ranges))
        for s in a.Strings where containsString(b.Strings, s) { r.Strings.append(s) }
        return r
    }

    func subtractSets(_ a: CharSet, _ b: CharSet) -> CharSet {
        let r = CharSet(ranges: subtractRanges(a.Ranges, b.Ranges))
        for s in a.Strings where !containsString(b.Strings, s) { r.Strings.append(s) }
        return r
    }

    /// parseClassSetOperand reads a nested class, an escape, \q{...}, or
    /// a character (and, where allowed, a range from it).
    func parseClassSetOperand(allowRange: bool) throws -> CharSet {
        if atEnd { throw fail("Unterminated character class") }
        let c = peek()
        if c == 0x5B {
            pos += 1
            let negate = eat(0x5E)
            let s = try parseClassSetExpression()
            if !eat(0x5D) { throw fail("Unterminated character class") }
            if negate {
                if !s.Strings.isEmpty { throw fail("Negated character class may contain strings") }
                return CharSet(ranges: complementRanges(s.Ranges))
            }
            return s
        }
        if c == 0x5C {
            pos += 1
            if atEnd { throw fail("\\ at end of pattern") }
            if peek() == 0x71 && peek(1) == 0x7B {
                pos += 2
                return try parseClassStrings()
            }
            if let s = try classEscape() { return s }
            pos -= 1
        }
        let lo = try classSetCharacter()
        if allowRange && peek() == 0x2D && peek(1) != 0x2D {
            pos += 1
            let hi = try classSetCharacter()
            if lo > hi { throw fail("Range out of order in character class") }
            return CharSet(ranges: [lo, hi])
        }
        return CharSet(ranges: [lo, lo])
    }

    /// classSetCharacter reads one character of a v-mode class, escaped or not.
    func classSetCharacter() throws -> uint32 {
        let c = peek()
        if c == 0x5C {
            pos += 1
            if peek() == 0x62 {
                pos += 1
                return 0x08
            }
            return try characterEscape(inClass: true)
        }
        if c == 0x28 || c == 0x29 || c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x2D || c == 0x7C {
            throw fail("Invalid character in character class")
        }
        if isClassSetReservedPunctuator(c) && peek(1) == c {
            throw fail("Invalid set operation in character class")
        }
        pos += 1
        return c
    }

    /// parseClassStrings reads \q{a|bc|} after the {.
    func parseClassStrings() throws -> CharSet {
        let set = CharSet()
        var cur: [uint32] = []
        while true {
            if atEnd { throw fail("Unterminated character class") }
            let c = peek()
            if c == 0x7D {
                pos += 1
                set.addString(cur)
                break
            }
            if c == 0x7C {
                pos += 1
                set.addString(cur)
                cur = []
                continue
            }
            if c == 0x5C {
                pos += 1
                if peek() == 0x62 {
                    pos += 1
                    cur.append(0x08)
                } else {
                    cur.append(try characterEscape(inClass: true))
                }
                continue
            }
            cur.append(try classSetCharacter())
        }
        return set
    }

    // MARK: property escapes

    func parseProperty(negated: bool) throws -> CharSet {
        if !eat(0x7B) { throw fail("Invalid property name") }
        var name: [uint8] = []
        var val: [uint8] = []
        var inValue = false
        while true {
            if atEnd { throw fail("Invalid property name") }
            let c = peek()
            pos += 1
            if c == 0x7D { break }
            if c == 0x3D && !inValue {
                inValue = true
                continue
            }
            let ok = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x5F
            if !ok { throw fail("Invalid property name") }
            if inValue { val.append(uint8(c)) } else { name.append(uint8(c)) }
        }
        let n = string(decoding: name, as: UTF8.self)
        let v = string(decoding: val, as: UTF8.self)
        if n.isEmpty || (inValue && v.isEmpty) { throw fail("Invalid property name") }
        var set: CharSet
        if inValue {
            set = try propertyValue(n, v)
        } else if let s = lonePropertyOfStrings(n) {
            if !vmode || negated { throw fail("Invalid property name") }
            return s
        } else {
            set = try loneProperty(n)
        }
        if negated { set = CharSet(ranges: complementRanges(set.Ranges)) }
        return set
    }

    func propertyValue(_ n: string, _ v: string) throws -> CharSet {
        if n == "General_Category" || n == "gc" {
            if unicode.CategoryAbbreviation(v) != nil, let s = unicode.CategoryRanges(v) {
                return CharSet(ranges: s.Ranges)
            }
        } else if n == "Script" || n == "sc" || n == "Script_Extensions" || n == "scx" {
            if let long = unicode.ScriptName(v) {
                let ext = n == "Script_Extensions" || n == "scx"
                return CharSet(ranges: unicode.ScriptRanges(long, extensions: ext).Ranges)
            }
        }
        throw fail("Invalid property name")
    }

    func loneProperty(_ n: string) throws -> CharSet {
        if n == "Any" { return CharSet(ranges: [0, MaxCodePoint]) }
        if n == "ASCII" { return CharSet(ranges: [0, 0x7F]) }
        if n == "Assigned" {
            if let cn = unicode.CategoryRanges("Cn") { return CharSet(ranges: complementRanges(cn.Ranges)) }
        }
        if unicode.CategoryAbbreviation(n) != nil, let s = unicode.CategoryRanges(n) {
            return CharSet(ranges: s.Ranges)
        }
        if binaryProperties.contains(n), let p = unicode.Property(n) {
            return CharSet(ranges: p.Ranges)
        }
        throw fail("Invalid property name")
    }

    /// lonePropertyOfStrings is a v-mode property of strings (§22.2.2.9.2).
    /// ZWJ and tag sequences need the UCD's emoji sequence files, which
    /// the unicode package does not have yet: they match nothing.
    func lonePropertyOfStrings(_ n: string) -> CharSet? {
        switch n {
        case "Emoji_Keycap_Sequence":
            return keycapSequences()
        case "RGI_Emoji_Modifier_Sequence":
            return modifierSequences()
        case "RGI_Emoji_Flag_Sequence":
            return flagSequences()
        case "Basic_Emoji":
            return basicEmoji()
        case "RGI_Emoji_Tag_Sequence", "RGI_Emoji_ZWJ_Sequence":
            return CharSet()
        case "RGI_Emoji":
            let s = basicEmoji()
            s.addSet(keycapSequences())
            s.addSet(modifierSequences())
            s.addSet(flagSequences())
            return s
        default:
            return nil
        }
    }

    func keycapSequences() -> CharSet {
        let s = CharSet()
        let keys: [uint32] = [0x23, 0x2A, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]
        for c in keys {
            s.addString([c, 0xFE0F, 0x20E3])
        }
        return s
    }

    func modifierSequences() -> CharSet {
        let s = CharSet()
        guard let bases = unicode.Property("Emoji_Modifier_Base") else { return s }
        var i = 0
        while i + 1 < bases.Ranges.count {
            var c = bases.Ranges[i]
            while c <= bases.Ranges[i + 1] {
                var m: uint32 = 0x1F3FB
                while m <= 0x1F3FF {
                    s.Strings.append([c, m])
                    m += 1
                }
                c += 1
            }
            i += 2
        }
        return s
    }

    func flagSequences() -> CharSet {
        let s = CharSet()
        for code in regionCodes {
            let b = [uint8](code.utf8)
            s.Strings.append([0x1F1E6 + uint32(b[0] - 0x41), 0x1F1E6 + uint32(b[1] - 0x41)])
        }
        return s
    }

    func basicEmoji() -> CharSet {
        let s = CharSet()
        if let pres = unicode.Property("Emoji_Presentation") {
            s.Ranges = unionRanges(s.Ranges, pres.Ranges)
            if let emoji = unicode.Property("Emoji") {
                // Text-default emoji take U+FE0F to present as emoji.
                let textDefault = subtractRanges(emoji.Ranges, pres.Ranges)
                var i = 0
                while i + 1 < textDefault.count {
                    var c = textDefault[i]
                    while c <= textDefault[i + 1] {
                        if c > 0x7F { s.Strings.append([c, 0xFE0F]) }
                        c += 1
                    }
                    i += 2
                }
            }
        }
        return s
    }
}

// MARK: character tests

func hexValue(_ c: uint32) -> int {
    if c >= 0x30 && c <= 0x39 { return int(c - 0x30) }
    if c >= 0x61 && c <= 0x66 { return int(c - 0x61 + 10) }
    if c >= 0x41 && c <= 0x46 { return int(c - 0x41 + 10) }
    return -1
}

func isSyntaxCharacter(_ c: uint32) -> bool {
    switch c {
    case 0x5E, 0x24, 0x5C, 0x2E, 0x2A, 0x2B, 0x3F, 0x28, 0x29, 0x5B, 0x5D, 0x7B, 0x7D, 0x7C: return true
    default: return false
    }
}

/// isClassSetReservedPunctuator is & - ! # % , : ; < = > @ ` ~.
func isClassSetReservedPunctuator(_ c: uint32) -> bool {
    switch c {
    case 0x26, 0x2D, 0x21, 0x23, 0x25, 0x2C, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x40, 0x60, 0x7E: return true
    default: return false
    }
}

func toUnits(_ cps: [uint32]) -> [uint16] {
    var out: [uint16] = []
    for c in cps {
        if c >= 0x10000 {
            let v = c - 0x10000
            out.append(uint16(0xD800 + (v >> 10)))
            out.append(uint16(0xDC00 + (v & 0x3FF)))
        } else {
            out.append(uint16(c))
        }
    }
    return out
}

/// binaryProperties are the binary properties §22.2.2.9 allows, by
/// canonical name and alias (Table 69).
let binaryProperties: [string] = [
    "ASCII_Hex_Digit", "AHex", "Alphabetic", "Alpha", "Bidi_Control", "Bidi_C",
    "Bidi_Mirrored", "Bidi_M", "Case_Ignorable", "CI", "Cased", "Changes_When_Casefolded", "CWCF",
    "Changes_When_Casemapped", "CWCM", "Changes_When_Lowercased", "CWL",
    "Changes_When_NFKC_Casefolded", "CWKCF", "Changes_When_Titlecased", "CWT",
    "Changes_When_Uppercased", "CWU", "Dash", "Default_Ignorable_Code_Point", "DI",
    "Deprecated", "Dep", "Diacritic", "Dia", "Emoji", "Emoji_Component", "EComp",
    "Emoji_Modifier", "EMod", "Emoji_Modifier_Base", "EBase", "Emoji_Presentation", "EPres",
    "Extended_Pictographic", "ExtPict", "Extender", "Ext", "Grapheme_Base", "Gr_Base",
    "Grapheme_Extend", "Gr_Ext", "Hex_Digit", "Hex", "IDS_Binary_Operator", "IDSB",
    "IDS_Trinary_Operator", "IDST", "ID_Continue", "IDC", "ID_Start", "IDS", "Ideographic", "Ideo",
    "Join_Control", "Join_C", "Logical_Order_Exception", "LOE", "Lowercase", "Lower", "Math",
    "Noncharacter_Code_Point", "NChar", "Pattern_Syntax", "Pat_Syn", "Pattern_White_Space", "Pat_WS",
    "Quotation_Mark", "QMark", "Radical", "Regional_Indicator", "RI", "Sentence_Terminal", "STerm",
    "Soft_Dotted", "SD", "Terminal_Punctuation", "Term", "Unified_Ideograph", "UIdeo",
    "Uppercase", "Upper", "Variation_Selector", "VS", "White_Space", "space", "XID_Continue", "XIDC",
    "XID_Start", "XIDS",
]

/// regionCodes are the ISO 3166-1 regions with RGI flag emoji.
let regionCodes: [string] = [
    "AC", "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "AS", "AT", "AU", "AW", "AX", "AZ",
    "BA", "BB", "BD", "BE", "BF", "BG", "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS", "BT", "BV", "BW", "BY", "BZ",
    "CA", "CC", "CD", "CF", "CG", "CH", "CI", "CK", "CL", "CM", "CN", "CO", "CP", "CR", "CU", "CV", "CW", "CX", "CY", "CZ",
    "DE", "DG", "DJ", "DK", "DM", "DO", "DZ", "EA", "EC", "EE", "EG", "EH", "ER", "ES", "ET", "EU",
    "FI", "FJ", "FK", "FM", "FO", "FR", "GA", "GB", "GD", "GE", "GF", "GG", "GH", "GI", "GL", "GM", "GN", "GP", "GQ", "GR", "GS", "GT", "GU", "GW", "GY",
    "HK", "HM", "HN", "HR", "HT", "HU", "IC", "ID", "IE", "IL", "IM", "IN", "IO", "IQ", "IR", "IS", "IT",
    "JE", "JM", "JO", "JP", "KE", "KG", "KH", "KI", "KM", "KN", "KP", "KR", "KW", "KY", "KZ",
    "LA", "LB", "LC", "LI", "LK", "LR", "LS", "LT", "LU", "LV", "LY",
    "MA", "MC", "MD", "ME", "MF", "MG", "MH", "MK", "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT", "MU", "MV", "MW", "MX", "MY", "MZ",
    "NA", "NC", "NE", "NF", "NG", "NI", "NL", "NO", "NP", "NR", "NU", "NZ", "OM",
    "PA", "PE", "PF", "PG", "PH", "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PW", "PY", "QA",
    "RE", "RO", "RS", "RU", "RW", "SA", "SB", "SC", "SD", "SE", "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "SN", "SO", "SR", "SS", "ST", "SV", "SX", "SY", "SZ",
    "TA", "TC", "TD", "TF", "TG", "TH", "TJ", "TK", "TL", "TM", "TN", "TO", "TR", "TT", "TV", "TW", "TZ",
    "UA", "UG", "UM", "UN", "US", "UY", "UZ", "VA", "VC", "VE", "VG", "VI", "VN", "VU",
    "WF", "WS", "XK", "YE", "YT", "ZA", "ZM", "ZW",
]
