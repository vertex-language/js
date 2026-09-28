package regexp

import "js/regexp/syntax"

/// RegExpMatch holds match coordinates and capture groups.
public struct RegExpMatch {
    public let Matched: bool
    public let Start: int
    public let End: int
    public let Captures: [string]

    public init(matched: bool, start: int = 0, end: int = 0, captures: [string] = []) {
        self.Matched = matched
        self.Start = start
        self.End = end
        self.Captures = captures
    }
}

/// RegExp is an ECMAScript regular expression matcher.
public final class RegExp {
    public let Pattern: syntax.Pattern

    public init(pattern: syntax.Pattern) {
        self.Pattern = pattern
    }

    /// Compile parses and compiles a pattern with flags.
    public static func Compile(_ pattern: string, flags: string = "") throws -> RegExp {
        let p = try syntax.Parse(pattern, flags: flags)
        return RegExp(pattern: p)
    }

    /// Test returns whether the pattern matches anywhere in text.
    public func Test(_ text: string) -> bool {
        let m = Exec(text)
        return m != nil
    }

    /// Exec executes a search for a match in a specified string.
    public func Exec(_ text: string, fromIndex: int = 0) -> RegExpMatch? {
        let bytes = [uint8](text.utf8)
        var start = fromIndex < 0 ? 0 : fromIndex
        if start > bytes.count { return nil }

        while start <= bytes.count {
            if let endPos = matchNode(Pattern.Root, at: start, bytes: bytes) {
                var sub: [uint8] = []
                for i in start..<endPos { sub.append(bytes[i]) }
                let matchedStr = String(decoding: sub, as: UTF8.self)
                return RegExpMatch(matched: true, start: start, end: endPos, captures: [matchedStr])
            }
            start += 1
        }

        return nil
    }

    func matchNode(_ node: syntax.Node, at pos: int, bytes: [uint8]) -> int? {
        switch node.Kind {
        case .empty:
            return pos

        case .literal(let ch):
            if pos < bytes.count && uint32(bytes[pos]) == ch {
                return pos + 1
            }
            return nil

        case .anyChar:
            if pos < bytes.count {
                let b = bytes[pos]
                if !Pattern.Flags.DotAll && (b == 0x0A || b == 0x0D) {
                    return nil
                }
                return pos + 1
            }
            return nil

        case .startOfLine:
            if pos == 0 { return pos }
            if Pattern.Flags.Multiline && pos > 0 && (bytes[pos - 1] == 0x0A || bytes[pos - 1] == 0x0D) {
                return pos
            }
            return nil

        case .endOfLine:
            if pos == bytes.count { return pos }
            if Pattern.Flags.Multiline && (bytes[pos] == 0x0A || bytes[pos] == 0x0D) {
                return pos
            }
            return nil

        case .sequence(let nodes):
            return matchSeq(nodes: nodes, idx: 0, pos: pos, bytes: bytes)

        case .alternate(let branches):
            for b in branches {
                if let endPos = matchNode(b, at: pos, bytes: bytes) {
                    return endPos
                }
            }
            return nil

        case .repeatOp(let inner, let min, let max, _):
            var matches = [pos]
            var cur = pos
            while matches.count - 1 < max {
                if let next = matchNode(inner, at: cur, bytes: bytes), next > cur {
                    matches.append(next)
                    cur = next
                } else {
                    break
                }
            }
            if matches.count - 1 >= min {
                return matches[matches.count - 1]
            }
            return nil

        case .captureGroup(let inner, _):
            return matchNode(inner, at: pos, bytes: bytes)
        }
    }

    func matchSeq(nodes: [syntax.Node], idx: int, pos: int, bytes: [uint8]) -> int? {
        if idx >= nodes.count {
            return pos
        }
        let cur = nodes[idx]
        if case .repeatOp(let inner, let min, let max, _) = cur.Kind {
            var matches = [pos]
            var p = pos
            while matches.count - 1 < max {
                if let next = matchNode(inner, at: p, bytes: bytes), next > p {
                    matches.append(next)
                    p = next
                } else {
                    break
                }
            }
            var k = matches.count - 1
            while k >= min {
                let matchPos = matches[k]
                if let finalPos = matchSeq(nodes: nodes, idx: idx + 1, pos: matchPos, bytes: bytes) {
                    return finalPos
                }
                k -= 1
            }
            return nil
        } else {
            if let next = matchNode(cur, at: pos, bytes: bytes) {
                return matchSeq(nodes: nodes, idx: idx + 1, pos: next, bytes: bytes)
            }
            return nil
        }
    }
}
