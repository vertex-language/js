// Package regexp compiles a js/regexp/syntax tree to a program for a
// backtracking matcher over UTF-16 code units, with the semantics of
// ECMA-262 §22.2.2: captures reset on each iteration of a quantifier, an
// iteration past the minimum may not match empty, lookbehind matches
// right to left, and case-insensitive matching compares Canonicalize(ch)
// -- simple case folding under u or v, and toUpperCase otherwise.
//
// The matcher keeps its own backtrack stack rather than recursing, so a
// long input cannot overflow the native stack. Every capture or register
// write pushes its old value, and backtracking undoes them in order.
package regexp

import (
    "js/regexp/syntax"
    "unicode"
)

// MARK: the program

enum Op {
    case char         // A: the character (canonicalized when C is 1)
    case any          // A: 1 when dotAll
    case set          // A: the set's index, B: 1 negated, C: 1 case-insensitive
    case lineStart    // A: 1 multiline
    case lineEnd      // A: 1 multiline
    case wordBoundary // A: 1 negated (\B), B: 1 ignoreCase under unicode mode
    case split        // A: tried first, B: on backtracking
    case jump         // A
    case save         // A: the capture slot
    case resetCaps    // A, B: the first and last group an iteration resets
    case backref      // A: index into refs, C: 1 case-insensitive
    case look         // A: body start, B: where to go after, C: 1 negated
    case loopInit     // A: the loop's registers (count, then the iteration's start)
    case loopHead     // A: registers, B: min, C: max (-1 none), D: exit; Greedy
    case loopBody     // A: registers: note where this iteration starts
    case loopTail     // A: registers, B: min, C: the head
    case repeatAtom   // A: min, B: max (-1 none); the atom is the next instruction; Greedy
    case succeed      // a lookaround body matched
    case match        // the pattern matched
}

struct Inst {
    var Op: Op
    var A: int = 0
    var B: int = 0
    var C: int = 0
    var D: int = 0
    var Greedy: bool = true
    /// Back is set on an instruction that consumes input right to left
    /// (inside a lookbehind).
    var Back: bool = false

    init(_ op: Op) {
        self.Op = op
    }
}

/// Program is a compiled regular expression.
public final class Program {
    public let Pattern: syntax.Pattern
    var code: [Inst] = []
    var sets: [syntax.CharSet] = []
    var refs: [[int]] = []
    var registers: int = 0
    let umode: bool
    /// firstChar is a code unit every match begins with, or -1.
    var firstChar: int = -1
    /// anchored is set when a match can only begin at 0.
    var anchored: bool = false
    var matcher: Matcher? = nil

    init(_ p: syntax.Pattern) {
        Pattern = p
        umode = p.Flags.UnicodeMode
    }

    public var GroupCount: int { return Pattern.GroupCount }
    public var Flags: syntax.Flags { return Pattern.Flags }
    public var GroupNames: [[uint16]] { return Pattern.GroupNames }

    /// Compile parses and compiles a pattern; a syntax.SyntaxError for an
    /// invalid one.
    public static func Compile(_ source: [uint16], _ flags: syntax.Flags) throws -> Program {
        let pat = try syntax.Parse(source, flags)
        let p = Program(pat)
        let c = Compiler(p)
        c.compile(pat.Root, back: false)
        c.emit(Inst(.match))
        p.registers = c.nextReg
        p.analyze()
        return p
    }

    /// analyze finds what lets a search skip positions.
    func analyze() {
        guard !code.isEmpty else { return }
        let first = code[0]
        if first.Op == .lineStart && first.A == 0 {
            anchored = true
        }
        if first.Op == .char && first.C == 0 && !first.Back {
            let c = first.A
            firstChar = c >= 0x10000 ? 0xD800 + ((c - 0x10000) >> 10) : c
        }
    }

    /// Exec finds the first match at or after start (only at start when
    /// sticky). The result is the captures' [start, end] pairs, -1 for
    /// one that did not participate; nil when there is no match.
    public func Exec(_ input: [uint16], _ start: int) -> [int]? {
        let m = matcher ?? Matcher(self)
        matcher = nil
        defer { matcher = m }
        m.begin(input)
        var i = start
        let n = input.count
        if Pattern.Flags.Sticky {
            return m.matchAt(i)
        }
        if anchored {
            return i == 0 ? m.matchAt(0) : nil
        }
        while i <= n {
            if firstChar >= 0 {
                while i < n && int(input[i]) != firstChar { i += 1 }
                if i >= n { return nil }
                // In unicode mode no match begins inside a surrogate pair.
                if umode && i > 0 && isTrail(input[i]) && isLead(input[i - 1]) {
                    i += 1
                    continue
                }
            }
            if let r = m.matchAt(i) { return r }
            if umode && i + 1 < n && isLead(input[i]) && isTrail(input[i + 1]) {
                i += 2
            } else {
                i += 1
            }
        }
        return nil
    }
}

func isLead(_ u: uint16) -> bool { return u >= 0xD800 && u <= 0xDBFF }
func isTrail(_ u: uint16) -> bool { return u >= 0xDC00 && u <= 0xDFFF }

// MARK: the compiler

final class Compiler {
    let p: Program
    var nextReg = 0

    init(_ p: Program) {
        self.p = p
    }

    @discardableResult
    func emit(_ i: Inst) -> int {
        p.code.append(i)
        return p.code.count - 1
    }

    var here: int { return p.code.count }

    func compile(_ n: syntax.Node, back: bool) {
        switch n.Kind {
        case .empty:
            break
        case .char(let c):
            var i = Inst(.char)
            i.A = n.IgnoreCase ? int(canonicalize(c, p.umode)) : int(c)
            i.C = n.IgnoreCase ? 1 : 0
            i.Back = back
            emit(i)
        case .dot:
            var i = Inst(.any)
            i.A = n.DotAll ? 1 : 0
            i.Back = back
            emit(i)
        case .set(let s, let negated):
            compileSet(s, negated, n.IgnoreCase, back)
        case .lineStart:
            var i = Inst(.lineStart)
            i.A = n.Multiline ? 1 : 0
            emit(i)
        case .lineEnd:
            var i = Inst(.lineEnd)
            i.A = n.Multiline ? 1 : 0
            emit(i)
        case .wordBoundary(let negated):
            var i = Inst(.wordBoundary)
            i.A = negated ? 1 : 0
            i.B = n.IgnoreCase && p.umode ? 1 : 0
            emit(i)
        case .seq(let nodes):
            if back {
                var k = nodes.count - 1
                while k >= 0 {
                    compile(nodes[k], back: back)
                    k -= 1
                }
            } else {
                for x in nodes { compile(x, back: back) }
            }
        case .alt(let alts):
            compileAlternatives(alts.count, back) { k in self.compile(alts[k], back: back) }
        case .group(let body, let index):
            var open = Inst(.save)
            open.A = back ? index * 2 + 1 : index * 2
            emit(open)
            compile(body, back: back)
            var close = Inst(.save)
            close.A = back ? index * 2 : index * 2 + 1
            emit(close)
        case .look(let body, let ahead, let negated):
            let at = emit(Inst(.look))
            p.code[at].A = at + 1
            p.code[at].C = negated ? 1 : 0
            compile(body, back: !ahead)
            emit(Inst(.succeed))
            p.code[at].B = here
        case .repeatNode(let atom, let lo, let hi, let greedy):
            compileRepeat(n, atom, lo, hi, greedy, back)
        case .backref:
            var i = Inst(.backref)
            p.refs.append(n.Groups)
            i.A = p.refs.count - 1
            i.C = n.IgnoreCase ? 1 : 0
            i.Back = back
            emit(i)
        }
    }

    /// compileAlternatives emits count alternatives, each tried in turn.
    func compileAlternatives(_ count: int, _ back: bool, _ body: (int) -> Void) {
        var jumps: [int] = []
        var k = 0
        while k < count {
            if k < count - 1 {
                let sp = emit(Inst(.split))
                p.code[sp].A = sp + 1
                body(k)
                jumps.append(emit(Inst(.jump)))
                p.code[sp].B = here
            } else {
                body(k)
            }
            k += 1
        }
        for j in jumps { p.code[j].A = here }
    }

    func compileSet(_ s: syntax.CharSet, _ negated: bool, _ ic: bool, _ back: bool) {
        if s.Strings.isEmpty || negated {
            emitSet(s, negated, ic, back)
            return
        }
        // A class with strings matches its longest string first (§22.2.2.9).
        let strs = s.Strings.sorted(by: { $0.count > $1.count })
        let hasSingles = !s.Ranges.isEmpty
        let total = strs.count + (hasSingles ? 1 : 0)
        compileAlternatives(total, back) { k in
            if k < strs.count {
                var chars = strs[k]
                if back { chars = chars.reversed() }
                for c in chars {
                    var i = Inst(.char)
                    i.A = ic ? int(canonicalize(c, self.p.umode)) : int(c)
                    i.C = ic ? 1 : 0
                    i.Back = back
                    self.emit(i)
                }
            } else {
                self.emitSet(syntax.CharSet(ranges: s.Ranges), false, ic, back)
            }
        }
    }

    func emitSet(_ s: syntax.CharSet, _ negated: bool, _ ic: bool, _ back: bool) {
        p.sets.append(s)
        var i = Inst(.set)
        i.A = p.sets.count - 1
        i.B = negated ? 1 : 0
        i.C = ic ? 1 : 0
        i.Back = back
        emit(i)
    }

    /// isSimple says an atom matches exactly one character and captures
    /// nothing, so a repeat of it needs no loop.
    func isSimple(_ n: syntax.Node) -> bool {
        switch n.Kind {
        case .char, .dot: return true
        case .set(let s, let negated): return s.Strings.isEmpty || negated
        default: return false
        }
    }

    func compileRepeat(_ n: syntax.Node, _ atom: syntax.Node, _ lo: int, _ hi: int, _ greedy: bool, _ back: bool) {
        if hi == 0 { return }
        if lo == 1 && hi == 1 {
            compile(atom, back: back)
            return
        }
        if isSimple(atom) {
            var r = Inst(.repeatAtom)
            r.A = lo
            r.B = hi
            r.Greedy = greedy
            r.Back = back
            emit(r)
            compile(atom, back: back)
            return
        }
        let regs = nextReg
        nextReg += 2
        var initI = Inst(.loopInit)
        initI.A = regs
        emit(initI)
        let head = emit(Inst(.loopHead))
        p.code[head].A = regs
        p.code[head].B = lo
        p.code[head].C = hi
        p.code[head].Greedy = greedy
        var body = Inst(.loopBody)
        body.A = regs
        emit(body)
        if n.LastGroup >= n.FirstGroup {
            var reset = Inst(.resetCaps)
            reset.A = n.FirstGroup
            reset.B = n.LastGroup
            emit(reset)
        }
        compile(atom, back: back)
        var tail = Inst(.loopTail)
        tail.A = regs
        tail.B = lo
        tail.C = head
        emit(tail)
        p.code[head].D = here
    }
}

// MARK: case folding

/// canonicalize is Canonicalize(rer, ch) (§22.2.2.7.3).
func canonicalize(_ c: uint32, _ umode: bool) -> uint32 {
    if umode { return unicode.CaseFold(c) }
    if c < 0x80 { return c >= 0x61 && c <= 0x7A ? c - 32 : c }
    if c > 0xFFFF { return c }
    return uint32(canonTable[int(c)])
}

/// canonTable is Canonicalize for every code unit without u or v:
/// toUppercase when that is one code unit and does not map a non-ASCII
/// unit to ASCII.
let canonTable: [uint16] = makeCanonTable()

func makeCanonTable() -> [uint16] {
    var t = [uint16](repeating: 0, count: 0x10000)
    var c = 0
    while c < 0x10000 {
        t[c] = uint16(c)
        if c >= 0x80 && !(c >= 0xD800 && c <= 0xDFFF) {
            let u = unicode.UppercaseMapping(uint32(c))
            if u.count == 1 && u[0] <= 0xFFFF && u[0] >= 0x80 { t[c] = uint16(u[0]) }
        } else if c >= 0x61 && c <= 0x7A {
            t[c] = uint16(c - 32)
        }
        c += 1
    }
    return t
}

/// canonOrbits maps a canonical unit to the units that canonicalize to
/// it, for the units where that is more than one.
let canonOrbits: [uint16: [uint16]] = makeCanonOrbits()

func makeCanonOrbits() -> [uint16: [uint16]] {
    var m: [uint16: [uint16]] = [:]
    var c = 0
    while c < 0x10000 {
        let k = canonTable[c]
        if int(k) != c {
            if var list = m[k] {
                list.append(uint16(c))
                m[k] = list
            } else {
                m[k] = [k, uint16(c)]
            }
        }
        c += 1
    }
    return m
}

/// foldOrbits maps a simple case folding to the code points that fold
/// to it, for the foldings shared by more than one: built once, from
/// CaseFold over every code point that has one (none past U+1E921).
let foldOrbits: [uint32: [uint32]] = makeFoldOrbits()

func makeFoldOrbits() -> [uint32: [uint32]] {
    var m: [uint32: [uint32]] = [:]
    var c: uint32 = 0
    while c <= 0x1E921 {
        let f = unicode.CaseFold(c)
        if f != c {
            if var list = m[f] {
                list.append(c)
                m[f] = list
            } else {
                m[f] = [f, c]
            }
        }
        c += 1
    }
    return m
}

/// orbit is every character that canonicalizes as c does.
func orbit(_ c: uint32, _ umode: bool) -> [uint32] {
    if umode {
        let f = unicode.CaseFold(c)
        return foldOrbits[f] ?? [c]
    }
    if c > 0xFFFF { return [c] }
    let k = canonTable[int(c)]
    if let list = canonOrbits[k] {
        var out: [uint32] = []
        for x in list { out.append(uint32(x)) }
        return out
    }
    return [c]
}

// MARK: the matcher

// Backtrack entries, four ints each: kind, then three values.
let kBranch = 0      // pc, pos
let kCapture = 1     // slot, old value
let kRegister = 2    // register, old value
let kGreedy = 3      // repeat pc, the least position, the current one
let kLazy = 4        // repeat pc, count, position

final class Matcher {
    let p: Program
    let code: [Inst]
    var input: [uint16] = []
    var n: int = 0
    var caps: [int]
    var regs: [int]
    /// stack holds backtrack entries up to sp; it only grows, so a match
    /// allocates nothing once it has been as deep before.
    var stack: [int] = []
    var sp: int = 0

    init(_ p: Program) {
        self.p = p
        self.code = p.code
        caps = [int](repeating: -1, count: (p.Pattern.GroupCount + 1) * 2)
        regs = [int](repeating: 0, count: p.registers)
    }

    func begin(_ s: [uint16]) {
        input = s
        n = s.count
    }

    func matchAt(_ start: int) -> [int]? {
        var i = 0
        while i < caps.count {
            caps[i] = -1
            i += 1
        }
        sp = 0
        let end = run(0, start)
        if end < 0 { return nil }
        caps[0] = start
        caps[1] = end
        return caps
    }

    // MARK: reading characters

    /// forward reads the character at pos: (cp, width), width 0 at the end.
    func forward(_ pos: int) -> (uint32, int) {
        if pos >= n { return (0, 0) }
        let u = input[pos]
        if p.umode && isLead(u) && pos + 1 < n && isTrail(input[pos + 1]) {
            return (0x10000 + ((uint32(u) - 0xD800) << 10) + (uint32(input[pos + 1]) - 0xDC00), 2)
        }
        return (uint32(u), 1)
    }

    /// backward reads the character before pos.
    func backward(_ pos: int) -> (uint32, int) {
        if pos <= 0 { return (0, 0) }
        let u = input[pos - 1]
        if p.umode && isTrail(u) && pos >= 2 && isLead(input[pos - 2]) {
            return (0x10000 + ((uint32(input[pos - 2]) - 0xD800) << 10) + (uint32(u) - 0xDC00), 2)
        }
        return (uint32(u), 1)
    }

    func isLineTerminator(_ c: uint32) -> bool {
        return c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
    }

    func isWord(_ pos: int, _ foldWord: bool) -> bool {
        if pos < 0 || pos >= n { return false }
        let c = uint32(input[pos])
        if isAsciiWord(c) { return true }
        // Under iu, what folds to a word character is one (ſ, K).
        return foldWord && isAsciiWord(unicode.CaseFold(c))
    }

    func isAsciiWord(_ c: uint32) -> bool {
        return (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39) || c == 0x5F
    }

    func inSet(_ ins: Inst, _ c: uint32) -> bool {
        let s = p.sets[ins.A]
        var hit = s.Contains(c)
        if !hit && ins.C == 1 {
            for o in orbit(c, p.umode) where o != c && s.Contains(o) {
                hit = true
                break
            }
        }
        return ins.B == 1 ? !hit : hit
    }

    /// step matches one simple atom at pos; the new position, or -1.
    func step(_ ins: Inst, _ pos: int) -> int {
        let (c, w) = ins.Back ? backward(pos) : forward(pos)
        if w == 0 { return -1 }
        var ok = false
        switch ins.Op {
        case .char:
            ok = ins.C == 1 ? canonicalize(c, p.umode) == uint32(ins.A) : c == uint32(ins.A)
        case .any:
            ok = ins.A == 1 || !isLineTerminator(c)
        case .set:
            ok = inSet(ins, c)
        default:
            ok = false
        }
        if !ok { return -1 }
        return ins.Back ? pos - w : pos + w
    }

    // MARK: running

    func push(_ k: int, _ a: int, _ b: int, _ c: int) {
        if sp + 4 > stack.count {
            stack.append(k)
            stack.append(a)
            stack.append(b)
            stack.append(c)
        } else {
            stack[sp] = k
            stack[sp + 1] = a
            stack[sp + 2] = b
            stack[sp + 3] = c
        }
        sp += 4
    }

    func setCap(_ slot: int, _ v: int) {
        push(kCapture, slot, caps[slot], 0)
        caps[slot] = v
    }

    func setReg(_ r: int, _ v: int) {
        push(kRegister, r, regs[r], 0)
        regs[r] = v
    }

    /// run matches from pc at pos until a match or succeed; its position,
    /// or -1 once every alternative above the stack's current height fails.
    func run(_ startPC: int, _ startPos: int) -> int {
        let base = sp
        var pc = startPC
        var pos = startPos
        while true {
            let ins = code[pc]
            var fail = false
            switch ins.Op {
            case .char, .any, .set:
                let next = step(ins, pos)
                if next < 0 { fail = true } else { pos = next; pc += 1 }
            case .lineStart:
                if pos == 0 || (ins.A == 1 && isLineTerminator(uint32(input[pos - 1]))) { pc += 1 } else { fail = true }
            case .lineEnd:
                if pos == n || (ins.A == 1 && isLineTerminator(uint32(input[pos]))) { pc += 1 } else { fail = true }
            case .wordBoundary:
                let fold = ins.B == 1
                let at = isWord(pos - 1, fold) != isWord(pos, fold)
                if at != (ins.A == 1) { pc += 1 } else { fail = true }
            case .split:
                push(kBranch, ins.B, pos, 0)
                pc = ins.A
            case .jump:
                pc = ins.A
            case .save:
                setCap(ins.A, pos)
                pc += 1
            case .resetCaps:
                var g = ins.A
                while g <= ins.B {
                    if caps[g * 2] != -1 { setCap(g * 2, -1) }
                    if caps[g * 2 + 1] != -1 { setCap(g * 2 + 1, -1) }
                    g += 1
                }
                pc += 1
            case .backref:
                let next = backref(ins, pos)
                if next < 0 { fail = true } else { pos = next; pc += 1 }
            case .look:
                let height = sp
                let r = run(ins.A, pos)
                if ins.C == 0 {
                    if r < 0 {
                        fail = true
                    } else {
                        // Keep what the body captured, forgetting its
                        // alternatives: a lookaround is atomic.
                        keepUndo(from: height)
                        pc = ins.B
                    }
                } else {
                    if r >= 0 {
                        unwind(to: height)
                        fail = true
                    } else {
                        pc = ins.B
                    }
                }
            case .loopInit:
                setReg(ins.A, 0)
                setReg(ins.A + 1, -1)
                pc += 1
            case .loopHead:
                let count = regs[ins.A]
                if count < ins.B {
                    pc += 1
                } else if ins.C >= 0 && count >= ins.C {
                    pc = ins.D
                } else if ins.Greedy {
                    push(kBranch, ins.D, pos, 0)
                    pc += 1
                } else {
                    push(kBranch, pc + 1, pos, 0)
                    pc = ins.D
                }
            case .loopBody:
                setReg(ins.A + 1, pos)
                pc += 1
            case .loopTail:
                let count = regs[ins.A]
                if count >= ins.B && pos == regs[ins.A + 1] {
                    // An iteration past the minimum that matched nothing.
                    fail = true
                } else {
                    setReg(ins.A, count + 1)
                    pc = ins.C
                }
            case .repeatAtom:
                let atom = code[pc + 1]
                var count = 0
                var cur = pos
                if ins.Greedy {
                    var least = -1
                    while ins.B < 0 || count < ins.B {
                        if count == ins.A { least = cur }
                        let next = step(atom, cur)
                        if next < 0 { break }
                        cur = next
                        count += 1
                    }
                    if count < ins.A {
                        fail = true
                    } else {
                        if count == ins.A { least = cur }
                        if cur != least { push(kGreedy, pc, least, cur) }
                        pos = cur
                        pc += 2
                    }
                } else {
                    while count < ins.A {
                        let next = step(atom, cur)
                        if next < 0 { break }
                        cur = next
                        count += 1
                    }
                    if count < ins.A {
                        fail = true
                    } else {
                        if ins.B < 0 || count < ins.B { push(kLazy, pc, count, cur) }
                        pos = cur
                        pc += 2
                    }
                }
            case .succeed, .match:
                return pos
            }
            if !fail { continue }
            // Backtrack to the most recent alternative above base.
            var resumed = false
            while sp > base {
                sp -= 4
                let k = stack[sp]
                let a = stack[sp + 1]
                let b = stack[sp + 2]
                let c = stack[sp + 3]
                if k == kCapture {
                    caps[a] = b
                } else if k == kRegister {
                    regs[a] = b
                } else if k == kBranch {
                    pc = a
                    pos = b
                    resumed = true
                    break
                } else if k == kGreedy {
                    // Give back one character.
                    let atom = code[a + 1]
                    var cur = c
                    if atom.Back {
                        let (_, w) = forward(cur)
                        cur += w == 0 ? 1 : w
                    } else {
                        let (_, w) = backward(cur)
                        cur -= w == 0 ? 1 : w
                    }
                    if atom.Back ? cur < b : cur > b { push(kGreedy, a, b, cur) }
                    pc = a + 2
                    pos = cur
                    resumed = true
                    break
                } else if k == kLazy {
                    // Take one more.
                    let rep = code[a]
                    let next = step(code[a + 1], c)
                    if next < 0 { continue }
                    if rep.B < 0 || b + 1 < rep.B { push(kLazy, a, b + 1, next) }
                    pc = a + 2
                    pos = next
                    resumed = true
                    break
                }
            }
            if !resumed { return -1 }
        }
    }

    /// keepUndo drops the alternatives a lookaround body left above height
    /// but keeps its undo records, so backtracking past the lookaround
    /// still restores the captures it set.
    func keepUndo(from height: int) {
        var out = height
        var i = height
        while i < sp {
            let k = stack[i]
            if k == kCapture || k == kRegister {
                stack[out] = k
                stack[out + 1] = stack[i + 1]
                stack[out + 2] = stack[i + 2]
                stack[out + 3] = stack[i + 3]
                out += 4
            }
            i += 4
        }
        sp = out
    }

    /// unwind undoes everything above height.
    func unwind(to height: int) {
        while sp > height {
            sp -= 4
            let k = stack[sp]
            if k == kCapture {
                caps[stack[sp + 1]] = stack[sp + 2]
            } else if k == kRegister {
                regs[stack[sp + 1]] = stack[sp + 2]
            }
        }
    }

    /// backref matches what a group captured (§22.2.2.7.2); a group that
    /// did not participate matches empty.
    func backref(_ ins: Inst, _ pos: int) -> int {
        var s = -1
        var e = -1
        for g in p.refs[ins.A] where caps[g * 2] >= 0 && caps[g * 2 + 1] >= 0 {
            s = caps[g * 2]
            e = caps[g * 2 + 1]
            break
        }
        if s < 0 { return pos }
        let len = e - s
        let from = ins.Back ? pos - len : pos
        if from < 0 || from + len > n { return -1 }
        if ins.C == 0 {
            var i = 0
            while i < len {
                if input[s + i] != input[from + i] { return -1 }
                i += 1
            }
        } else {
            var i = 0
            var j = 0
            while i < len {
                let (a, wa) = forwardAt(s + i, e)
                let (b, wb) = forwardAt(from + j, from + len)
                if wa == 0 || wb == 0 || canonicalize(a, p.umode) != canonicalize(b, p.umode) { return -1 }
                i += wa
                j += wb
            }
            if j != len { return -1 }
        }
        return ins.Back ? from : from + len
    }

    /// forwardAt reads a character at i without passing limit.
    func forwardAt(_ i: int, _ limit: int) -> (uint32, int) {
        if i >= limit { return (0, 0) }
        let u = input[i]
        if p.umode && isLead(u) && i + 1 < limit && isTrail(input[i + 1]) {
            return (0x10000 + ((uint32(u) - 0xD800) << 10) + (uint32(input[i + 1]) - 0xDC00), 2)
        }
        return (uint32(u), 1)
    }
}
