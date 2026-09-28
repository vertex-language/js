package syntax

/// RegExpFlags represents the parsed ECMAScript regular expression flags.
public struct RegExpFlags: Equatable {
    public var Global: bool
    public var IgnoreCase: bool
    public var Multiline: bool
    public var DotAll: bool
    public var Unicode: bool
    public var Sticky: bool

    public init(global: bool = false, ignoreCase: bool = false, multiline: bool = false, dotAll: bool = false, unicode: bool = false, sticky: bool = false) {
        self.Global = global
        self.IgnoreCase = ignoreCase
        self.Multiline = multiline
        self.DotAll = dotAll
        self.Unicode = unicode
        self.Sticky = sticky
    }

    /// Parse parses flag characters ('g', 'i', 'm', 's', 'u', 'y').
    public static func Parse(_ flagsStr: string) throws -> RegExpFlags {
        var flags = RegExpFlags()
        for b in [uint8](flagsStr.utf8) {
            switch b {
            case 0x67: flags.Global = true       // 'g'
            case 0x69: flags.IgnoreCase = true   // 'i'
            case 0x6D: flags.Multiline = true    // 'm'
            case 0x73: flags.DotAll = true       // 's'
            case 0x75, 0x76: flags.Unicode = true // 'u', 'v'
            case 0x79: flags.Sticky = true       // 'y'
            default: break
            }
        }
        return flags
    }
}

/// Pattern AST node kinds for regular expressions.
public enum NodeKind {
    case empty
    case literal(uint32)
    case anyChar
    case startOfLine
    case endOfLine
    case sequence([Node])
    case alternate([Node])
    case repeatOp(node: Node, min: int, max: int, greedy: bool)
    case captureGroup(node: Node, index: int)
}

/// Node is one element of a regular expression AST.
public final class Node {
    public let Kind: NodeKind

    public init(_ kind: NodeKind) {
        self.Kind = kind
    }
}

/// Pattern represents a parsed ECMAScript regular expression.
public final class Pattern {
    public let Root: Node
    public let Flags: RegExpFlags
    public let Raw: string

    public init(root: Node, flags: RegExpFlags, raw: string) {
        self.Root = root
        self.Flags = flags
        self.Raw = raw
    }
}

/// Parse parses an ECMAScript regular expression pattern and flags.
public func Parse(_ pattern: string, flags: string = "") throws -> Pattern {
    let f = try RegExpFlags.Parse(flags)
    let bytes = [uint8](pattern.utf8)
    var i = 0

    func parseTerm() -> Node {
        if i >= bytes.count { return Node(.empty) }
        let b = bytes[i]
        i += 1
        switch b {
        case 0x2E: // '.'
            return Node(.anyChar)
        case 0x5E: // '^'
            return Node(.startOfLine)
        case 0x24: // '$'
            return Node(.endOfLine)
        default:
            return Node(.literal(uint32(b)))
        }
    }

    var nodes: [Node] = []
    while i < bytes.count {
        let n = parseTerm()
        // Check for repeat quantifiers: *, +, ?
        if i < bytes.count {
            let q = bytes[i]
            if q == 0x2A { // '*'
                i += 1
                nodes.append(Node(.repeatOp(node: n, min: 0, max: Int.max, greedy: true)))
                continue
            } else if q == 0x2B { // '+'
                i += 1
                nodes.append(Node(.repeatOp(node: n, min: 1, max: Int.max, greedy: true)))
                continue
            } else if q == 0x3F { // '?'
                i += 1
                nodes.append(Node(.repeatOp(node: n, min: 0, max: 1, greedy: true)))
                continue
            }
        }
        nodes.append(n)
    }

    let root = nodes.count == 1 ? nodes[0] : Node(.sequence(nodes))
    return Pattern(root: root, flags: f, raw: pattern)
}
