// Package structured installs structured data (ECMA-262 §25): JSON,
// ArrayBuffer, SharedArrayBuffer, DataView, the typed arrays and Atomics.
package structured

import (
    "js/object"
    "js/str"
    "js/value"
)

typealias Value = object.Value

func key(_ s: string) -> value.PropertyKey { return value.PropertyKey.Named(s) }

/// Install defines JSON and the buffers.
public func Install(_ r: object.Realm) {
    installJSON(r)
    installBuffers(r)
}

// MARK: JSON.parse (§25.5.1)

/// RawJSON is the object JSON.rawJSON makes: its text is written as is.
public final class RawJSON: object.JSObject {
    public let Text: str.JSString
    public init(_ text: str.JSString) {
        self.Text = text
        super.init(proto: nil)
    }
}

/// Parser reads JSON text into values, recording where each primitive
/// came from for a reviver's context.source.
final class Parser {
    let u: [uint16]
    let r: object.Realm
    var pos = 0
    /// sources is, per holder serial, the source text of its primitive
    /// properties and the values they parsed to.
    var sources: [int: [value.PropertyKey: (str.JSString, Value)]] = [:]
    let trackSources: bool

    init(_ s: str.JSString, _ r: object.Realm, trackSources: bool) {
        self.u = s.Units
        self.r = r
        self.trackSources = trackSources
    }

    func context(_ at: int) -> string {
        // Line and column, both from 1, as V8 reports them.
        var line = 1
        var col = 1
        var i = 0
        while i < at && i < u.count {
            if u[i] == 10 { line += 1; col = 1 } else { col += 1 }
            i += 1
        }
        return "in JSON at position \(at) (line \(line) column \(col))"
    }

    func fail(_ msg: string, _ at: int) -> Error {
        return object.ThrowSyntaxError("\(msg) \(context(at))")
    }

    func unexpected(_ at: int) -> Error {
        if at >= u.count { return object.ThrowSyntaxError("Unexpected end of JSON input") }
        let tok = str.JSString([u[at]]).String
        let whole = str.JSString(u).String
        if u.count <= 40 {
            return object.ThrowSyntaxError("Unexpected token '\(tok)', \"\(whole)\" is not valid JSON")
        }
        let from = max(0, at - 10)
        let to = min(u.count, at + 11)
        var slice: [uint16] = []
        var i = from
        while i < to { slice.append(u[i]); i += 1 }
        let pre = from > 0 ? "..." : ""
        let post = to < u.count ? "..." : ""
        return object.ThrowSyntaxError("Unexpected token '\(tok)', \"\(pre)\(str.JSString(slice).String)\(post)\" is not valid JSON")
    }

    func skipSpace() {
        while pos < u.count {
            let c = u[pos]
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { pos += 1 } else { break }
        }
    }

    func parseTop() throws -> Value {
        skipSpace()
        let v = try parseValue(holder: nil, key: nil)
        skipSpace()
        if pos < u.count { throw fail("Unexpected non-whitespace character after JSON", pos) }
        return v
    }

    func record(_ holder: object.JSObject?, _ k: value.PropertyKey?, _ start: int, _ v: Value) {
        guard trackSources, let h = holder, let kk = k else { return }
        var slice: [uint16] = []
        var i = start
        while i < pos { slice.append(u[i]); i += 1 }
        if sources[h.Serial] == nil {
            let fresh: [value.PropertyKey: (str.JSString, Value)] = [:]
            sources[h.Serial] = fresh
        }
        sources[h.Serial]![kk] = (str.JSString(slice), v)
    }

    func parseValue(holder: object.JSObject?, key k: value.PropertyKey?) throws -> Value {
        if pos >= u.count { throw object.ThrowSyntaxError("Unexpected end of JSON input") }
        let start = pos
        let c = u[pos]
        switch c {
        case 0x7B:
            return try parseObject()
        case 0x5B:
            return try parseArray()
        case 0x22:
            let v = Value.string(try parseString())
            record(holder, k, start, v)
            return v
        case 0x74:
            try literal("true")
            record(holder, k, start, .bool(true))
            return .bool(true)
        case 0x66:
            try literal("false")
            record(holder, k, start, .bool(false))
            return .bool(false)
        case 0x6E:
            try literal("null")
            record(holder, k, start, .null)
            return .null
        default:
            if c == 0x2D || (c >= 0x30 && c <= 0x39) {
                let v = Value.number(try parseNumber())
                record(holder, k, start, v)
                return v
            }
            throw unexpected(pos)
        }
    }

    func literal(_ word: string) throws {
        for b in word.utf8 {
            if pos >= u.count { throw object.ThrowSyntaxError("Unexpected end of JSON input") }
            if u[pos] != uint16(b) { throw unexpected(pos) }
            pos += 1
        }
    }

    func parseNumber() throws -> float64 {
        let start = pos
        if u[pos] == 0x2D {
            pos += 1
            if pos >= u.count || u[pos] < 0x30 || u[pos] > 0x39 {
                throw fail("No number after minus sign", pos)
            }
        }
        if u[pos] == 0x30 {
            pos += 1
            if pos < u.count && u[pos] >= 0x30 && u[pos] <= 0x39 { throw fail("Unexpected number", pos) }
        } else {
            while pos < u.count && u[pos] >= 0x30 && u[pos] <= 0x39 { pos += 1 }
        }
        if pos < u.count && u[pos] == 0x2E {
            pos += 1
            if pos >= u.count || u[pos] < 0x30 || u[pos] > 0x39 { throw fail("Unterminated fractional number", pos) }
            while pos < u.count && u[pos] >= 0x30 && u[pos] <= 0x39 { pos += 1 }
        }
        if pos < u.count && (u[pos] == 0x65 || u[pos] == 0x45) {
            pos += 1
            if pos < u.count && (u[pos] == 0x2B || u[pos] == 0x2D) { pos += 1 }
            if pos >= u.count || u[pos] < 0x30 || u[pos] > 0x39 { throw fail("Exponent part is missing a number", pos) }
            while pos < u.count && u[pos] >= 0x30 && u[pos] <= 0x39 { pos += 1 }
        }
        var text: [uint16] = []
        var i = start
        while i < pos { text.append(u[i]); i += 1 }
        return value.StringToNumber(str.JSString(text))
    }

    func hex(_ c: uint16) -> int {
        if c >= 0x30 && c <= 0x39 { return int(c) - 0x30 }
        if c >= 0x41 && c <= 0x46 { return int(c) - 0x37 }
        if c >= 0x61 && c <= 0x66 { return int(c) - 0x57 }
        return -1
    }

    func parseString() throws -> str.JSString {
        pos += 1
        var out: [uint16] = []
        while true {
            if pos >= u.count { throw fail("Unterminated string", pos) }
            let c = u[pos]
            if c == 0x22 {
                pos += 1
                return str.JSString(out)
            }
            if c < 0x20 { throw fail("Bad control character in string literal", pos) }
            if c != 0x5C {
                out.append(c)
                pos += 1
                continue
            }
            pos += 1
            if pos >= u.count { throw fail("Unterminated string", pos) }
            let e = u[pos]
            switch e {
            case 0x22: out.append(0x22)
            case 0x5C: out.append(0x5C)
            case 0x2F: out.append(0x2F)
            case 0x62: out.append(0x08)
            case 0x66: out.append(0x0C)
            case 0x6E: out.append(0x0A)
            case 0x72: out.append(0x0D)
            case 0x74: out.append(0x09)
            case 0x75:
                var v = 0
                var k = 1
                while k <= 4 {
                    if pos + k >= u.count { throw fail("Bad Unicode escape", pos - 1) }
                    let h = hex(u[pos + k])
                    if h < 0 { throw fail("Bad Unicode escape", pos - 1) }
                    v = v * 16 + h
                    k += 1
                }
                out.append(uint16(v))
                pos += 4
            default:
                throw fail("Bad escaped character", pos - 1)
            }
            pos += 1
        }
    }

    func parseArray() throws -> Value {
        pos += 1
        let a = object.CreateArrayFromList(r, [])
        var list: [Value] = []
        skipSpace()
        if pos < u.count && u[pos] == 0x5D {
            pos += 1
            return .object(a)
        }
        while true {
            skipSpace()
            list.append(try parseValue(holder: a, key: value.PropertyKey.index(uint32(list.count))))
            skipSpace()
            if pos >= u.count { throw object.ThrowSyntaxError("Unexpected end of JSON input") }
            if u[pos] == 0x2C {
                pos += 1
                skipSpace()
                if pos < u.count && u[pos] == 0x5D { throw unexpected(pos) }
                continue
            }
            if u[pos] == 0x5D {
                pos += 1
                break
            }
            throw fail("Expected ',' or ']' after array element", pos)
        }
        a.Dense = list
        a.Length = uint32(list.count)
        return .object(a)
    }

    func parseObject() throws -> Value {
        pos += 1
        let o = object.JSObject(proto: r.ObjectPrototype)
        skipSpace()
        if pos < u.count && u[pos] == 0x7D {
            pos += 1
            return .object(o)
        }
        var first = true
        while true {
            skipSpace()
            if pos >= u.count { throw object.ThrowSyntaxError("Unexpected end of JSON input") }
            if u[pos] != 0x22 {
                throw fail(first ? "Expected property name or '}'" : "Expected double-quoted property name", pos)
            }
            first = false
            let name = try parseString()
            skipSpace()
            if pos >= u.count { throw object.ThrowSyntaxError("Unexpected end of JSON input") }
            if u[pos] != 0x3A { throw fail("Expected ':' after property name", pos) }
            pos += 1
            skipSpace()
            let k = value.PropertyKey.FromString(name)
            let v = try parseValue(holder: o, key: k)
            _ = try object.CreateDataProperty(o, k, v)
            skipSpace()
            if pos >= u.count { throw object.ThrowSyntaxError("Unexpected end of JSON input") }
            if u[pos] == 0x2C {
                pos += 1
                continue
            }
            if u[pos] == 0x7D {
                pos += 1
                break
            }
            throw fail("Expected ',' or '}' after property value", pos)
        }
        return .object(o)
    }
}

/// internalize is InternalizeJSONProperty (§25.5.1.1).
func internalize(_ r: object.Realm, _ p: Parser, _ holder: object.JSObject, _ name: value.PropertyKey, _ reviver: Value) throws -> Value {
    let val = try holder.Get(name, .object(holder))
    if case .object(let o) = val {
        if try object.IsArray(val) {
            let len = try object.LengthOfArrayLike(o)
            var i = 0
            while i < len {
                let k = value.PropertyKey.FromNumber(float64(i))
                let nv = try internalize(r, p, o, k, reviver)
                if nv.IsUndefined { _ = try o.Delete(k) } else { _ = try object.CreateDataProperty(o, k, nv) }
                i += 1
            }
        } else {
            for k in try o.OwnPropertyKeys() {
                if k.IsSymbol { continue }
                guard let d = try o.GetOwnProperty(k), d.Enumerable == true else { continue }
                let nv = try internalize(r, p, o, k, reviver)
                if nv.IsUndefined { _ = try o.Delete(k) } else { _ = try object.CreateDataProperty(o, k, nv) }
            }
        }
    }
    let ctx = object.JSObject(proto: r.ObjectPrototype)
    if !val.IsObject, let src = p.sources[holder.Serial]?[name], object.SameValue(src.1, val) {
        try object.CreateDataPropertyOrThrow(ctx, key("source"), .string(src.0))
    }
    return try object.Call(reviver, .object(holder), [object.KeyToValue(name), val, .object(ctx)])
}

// MARK: JSON.stringify (§25.5.2)

final class Serializer {
    let r: object.Realm
    var replacer: Value = .undefined
    var propertyList: [value.PropertyKey]? = nil
    var gap: [uint16] = []
    var indent: [uint16] = []
    /// stack is the objects being serialized and the key each was reached by.
    var stack: [(object.JSObject, value.PropertyKey?)] = []
    var out = str.Builder()

    init(_ r: object.Realm) { self.r = r }

    func constructorName(_ o: object.JSObject) -> string {
        if let c = try? o.Get(key("constructor"), .object(o)), case .object(let co) = c,
           let n = try? co.Get(key("name"), c), case .string(let ns) = n {
            return ns.String
        }
        return "Object"
    }

    func describeKey(_ holder: object.JSObject, _ k: value.PropertyKey?) -> string {
        guard let kk = k else { return "" }
        if holder is object.ArrayObject, case .index(let i) = kk { return "index \(i)" }
        return "property '\(kk.AsString.String)'"
    }

    func circular(_ at: int, _ k: value.PropertyKey?, _ holder: object.JSObject) -> Error {
        var msg = "Converting circular structure to JSON\n    --> starting at object with constructor '\(constructorName(stack[at].0))'"
        var i = at + 1
        while i < stack.count {
            msg += "\n    |     \(describeKey(stack[i - 1].0, stack[i].1)) -> object with constructor '\(constructorName(stack[i].0))'"
            i += 1
        }
        msg += "\n    --- \(describeKey(holder, k)) closes the circle"
        return object.ThrowTypeError(msg)
    }

    /// property is SerializeJSONProperty: false when the value is not
    /// serializable (undefined, a function, a symbol).
    func property(_ holder: object.JSObject, _ k: value.PropertyKey, _ v0: Value) throws -> bool {
        var v = v0
        var isBigInt = false
        if case .bigint = v { isBigInt = true }
        if v.IsObject || isBigInt {
            let toJSON = try object.GetV(v, key("toJSON"))
            if toJSON.IsCallable { v = try object.Call(toJSON, v, [object.KeyToValue(k)]) }
        }
        if !replacer.IsUndefined {
            v = try object.Call(replacer, .object(holder), [object.KeyToValue(k), v])
        }
        if case .object(let o) = v {
            if let raw = o as? RawJSON {
                out.Append(raw.Text)
                return true
            }
            switch o.Kind {
            case .number: v = .number(try object.ToNumber(v))
            case .string: v = .string(try object.ToString(v))
            case .boolean: v = o.PrimitiveValue
            case .bigint: v = o.PrimitiveValue
            default: break
            }
        }
        switch v {
        case .null:
            out.AppendASCII("null")
        case .bool(let b):
            out.AppendASCII(b ? "true" : "false")
        case .string(let s):
            Quote(s, &out)
        case .number(let d):
            if d.isFinite { out.Append(value.NumberToJSString(d)) } else { out.AppendASCII("null") }
        case .bigint:
            throw object.ThrowTypeError("Do not know how to serialize a BigInt")
        case .object(let o):
            if o.IsCallable { return false }
            if try object.IsArray(v) {
                try array(o, k, holder)
            } else {
                try objectValue(o, k, holder)
            }
        default:
            return false
        }
        return true
    }

    func enter(_ o: object.JSObject, _ k: value.PropertyKey, _ holder: object.JSObject) throws {
        var i = 0
        while i < stack.count {
            if stack[i].0 === o { throw circular(i, k, holder) }
            i += 1
        }
        stack.append((o, stack.isEmpty ? nil : k))
    }

    func newline() {
        if gap.isEmpty { return }
        out.AppendUnit(0x0A)
        out.Units.append(contentsOf: indent)
    }

    func objectValue(_ o: object.JSObject, _ k: value.PropertyKey, _ holder: object.JSObject) throws {
        try enter(o, k, holder)
        let stepback = indent
        indent.append(contentsOf: gap)
        var keys: [value.PropertyKey] = []
        if let pl = propertyList {
            keys = pl
        } else {
            for kk in try o.OwnPropertyKeys() {
                if kk.IsSymbol { continue }
                if let d = try o.GetOwnProperty(kk), d.Enumerable == true { keys.append(kk) }
            }
        }
        out.AppendUnit(0x7B)
        var any = false
        for kk in keys {
            let v = try o.Get(kk, .object(o))
            let mark = out.Units.count
            if any { out.AppendUnit(0x2C) }
            newline()
            Quote(kk.AsString, &out)
            out.AppendUnit(0x3A)
            if !gap.isEmpty { out.AppendUnit(0x20) }
            if try property(o, kk, v) {
                any = true
            } else {
                while out.Units.count > mark { out.Units.removeLast() }
            }
        }
        indent = stepback
        if any { newline() }
        out.AppendUnit(0x7D)
        stack.removeLast()
    }

    func array(_ o: object.JSObject, _ k: value.PropertyKey, _ holder: object.JSObject) throws {
        try enter(o, k, holder)
        let stepback = indent
        indent.append(contentsOf: gap)
        let len = try object.LengthOfArrayLike(o)
        out.AppendUnit(0x5B)
        var i = 0
        while i < len {
            if i > 0 { out.AppendUnit(0x2C) }
            newline()
            let kk = value.PropertyKey.FromNumber(float64(i))
            if !(try property(o, kk, try o.Get(kk, .object(o)))) { out.AppendASCII("null") }
            i += 1
        }
        indent = stepback
        if len > 0 { newline() }
        out.AppendUnit(0x5D)
        stack.removeLast()
    }
}

let hexLower: [uint16] = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102]

/// Quote is QuoteJSONString (§25.5.2.3).
public func Quote(_ s: str.JSString, _ out: inout str.Builder) {
    let u = s.Units
    out.AppendUnit(0x22)
    var i = 0
    while i < u.count {
        let c = u[i]
        switch c {
        case 0x08: out.AppendASCII("\\b")
        case 0x09: out.AppendASCII("\\t")
        case 0x0A: out.AppendASCII("\\n")
        case 0x0C: out.AppendASCII("\\f")
        case 0x0D: out.AppendASCII("\\r")
        case 0x22: out.AppendASCII("\\\"")
        case 0x5C: out.AppendASCII("\\\\")
        default:
            var lone = false
            if c >= 0xD800 && c <= 0xDBFF {
                if i + 1 < u.count && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF {
                    out.AppendUnit(c)
                    out.AppendUnit(u[i + 1])
                    i += 2
                    continue
                }
                lone = true
            } else if c >= 0xDC00 && c <= 0xDFFF {
                lone = true
            }
            if c < 0x20 || lone {
                out.AppendASCII("\\u")
                out.AppendUnit(hexLower[int(c >> 12)])
                out.AppendUnit(hexLower[int((c >> 8) & 15)])
                out.AppendUnit(hexLower[int((c >> 4) & 15)])
                out.AppendUnit(hexLower[int(c & 15)])
            } else {
                out.AppendUnit(c)
            }
        }
        i += 1
    }
    out.AppendUnit(0x22)
}

/// Stringify is JSON.stringify(value, replacer, space), or nil for
/// undefined.
public func Stringify(_ r: object.Realm, _ v: Value, _ replacerV: Value, _ spaceV: Value) throws -> str.JSString? {
    let s = Serializer(r)
    if case .object(let ro) = replacerV {
        if ro.IsCallable {
            s.replacer = replacerV
        } else if try object.IsArray(replacerV) {
            var list: [value.PropertyKey] = []
            var seen: [value.PropertyKey: bool] = [:]
            let len = try object.LengthOfArrayLike(ro)
            var i = 0
            while i < len {
                let el = try ro.Get(value.PropertyKey.FromNumber(float64(i)), replacerV)
                var item: value.PropertyKey? = nil
                switch el {
                case .string(let str): item = value.PropertyKey.FromString(str)
                case .number(let d): item = value.PropertyKey.FromString(value.NumberToJSString(d))
                case .object(let eo):
                    if eo.Kind == .string || eo.Kind == .number {
                        item = value.PropertyKey.FromString(try object.ToString(el))
                    }
                default: break
                }
                if let it = item, seen[it] == nil {
                    seen[it] = true
                    list.append(it)
                }
                i += 1
            }
            s.propertyList = list
        }
    }
    var space = spaceV
    if case .object(let so) = space {
        if so.Kind == .number { space = .number(try object.ToNumber(space)) } else if so.Kind == .string { space = .string(try object.ToString(space)) }
    }
    if case .number(let d) = space {
        let n = min(10, max(0, value.ToIntegerOrInfinity(d)))
        var g: [uint16] = []
        var i = 0
        while i < int(n) { g.append(0x20); i += 1 }
        s.gap = g
    } else if case .string(let gs) = space {
        var g = gs.Units
        while g.count > 10 { g.removeLast() }
        s.gap = g
    }
    let wrapper = object.JSObject(proto: r.ObjectPrototype)
    try object.CreateDataPropertyOrThrow(wrapper, value.PropertyKey.string(str.JSString.Empty), v)
    if !(try s.property(wrapper, value.PropertyKey.string(str.JSString.Empty), v)) { return nil }
    return s.out.Build()
}

func installJSON(_ r: object.Realm) {
    let json = object.JSObject(proto: r.ObjectPrototype)
    r.DefineGlobal("JSON", .object(json))
    json.DefineData(.symbol(value.SymToStringTag), .string(str.Name("JSON")), writable: false, enumerable: false, configurable: true)
    r.Method(json, "parse", 2) { _, args, _ in
        let text = try object.ToString(object.Arg(args, 0))
        let reviver = object.Arg(args, 1)
        let p = Parser(text, r, trackSources: reviver.IsCallable)
        let v = try p.parseTop()
        if !reviver.IsCallable { return v }
        let root = object.JSObject(proto: r.ObjectPrototype)
        let rootKey = value.PropertyKey.string(str.JSString.Empty)
        try object.CreateDataPropertyOrThrow(root, rootKey, v)
        if !v.IsObject {
            // The whole text, trimmed of the whitespace around it.
            var a = 0
            var b = p.u.count
            while a < b && (p.u[a] == 0x20 || p.u[a] == 0x09 || p.u[a] == 0x0A || p.u[a] == 0x0D) { a += 1 }
            while b > a && (p.u[b - 1] == 0x20 || p.u[b - 1] == 0x09 || p.u[b - 1] == 0x0A || p.u[b - 1] == 0x0D) { b -= 1 }
            p.sources[root.Serial] = [rootKey: (text.Slice(a, b), v)]
        }
        return try internalize(r, p, root, rootKey, reviver)
    }
    r.Method(json, "stringify", 3) { _, args, _ in
        guard let s = try Stringify(r, object.Arg(args, 0), object.Arg(args, 1), object.Arg(args, 2)) else { return .undefined }
        return .string(s)
    }
    r.Method(json, "rawJSON", 1) { _, args, _ in
        let s = try object.ToString(object.Arg(args, 0))
        let u = s.Units
        if u.isEmpty || u[0] == 0x09 || u[0] == 0x0A || u[0] == 0x0D || u[0] == 0x20 ||
           u[u.count - 1] == 0x09 || u[u.count - 1] == 0x0A || u[u.count - 1] == 0x0D || u[u.count - 1] == 0x20 {
            throw object.ThrowSyntaxError("Invalid value for JSON.rawJSON")
        }
        let p = Parser(s, r, trackSources: false)
        let v = try p.parseTop()
        if v.IsObject { throw object.ThrowSyntaxError("Invalid value for JSON.rawJSON") }
        let o = RawJSON(s)
        o.DefineData(key("rawJSON"), .string(s), writable: false, enumerable: true, configurable: false)
        _ = try o.PreventExtensions()
        return .object(o)
    }
    r.Method(json, "isRawJSON", 1) { _, args, _ in
        if case .object(let o) = object.Arg(args, 0), o is RawJSON { return .bool(true) }
        return .bool(false)
    }
}
