// Package text installs text processing (ECMA-262 §22): String, the
// String Iterator, and RegExp.
package text

import (
    "js/object"
    "js/str"
    "js/token"
    "js/value"
    "unicode"
    "unicode/norm"
    "unicode/utf16"
)

typealias Value = object.Value

func key(_ s: string) -> value.PropertyKey { return value.PropertyKey.Named(s) }

/// Install defines String and RegExp.
public func Install(_ r: object.Realm) {
    installString(r)
    installRegExp(r)
}

/// thisString is RequireObjectCoercible(this) then ToString.
func thisString(_ v: Value, _ method: string) throws -> str.JSString {
    if case .string(let s) = v { return s }
    if v.IsNullish {
        throw object.ThrowTypeError("String.prototype.\(method) called on null or undefined")
    }
    return try object.ToString(v)
}

func thisStringValue(_ v: Value, _ method: string) throws -> str.JSString {
    if case .string(let s) = v { return s }
    if case .object(let o) = v, let so = o as? object.StringObject { return so.Str }
    throw object.ThrowTypeError("String.prototype.\(method) requires that 'this' be a String")
}

func units(_ u: [uint16], _ from: int, _ to: int) -> str.JSString {
    if from >= to { return str.JSString.Empty }
    var out: [uint16] = []
    out.reserveCapacity(to - from)
    var i = from
    while i < to { out.append(u[i]); i += 1 }
    return str.JSString(out)
}

func clampIndex(_ d: float64, _ len: int) -> int {
    if d < 0 { return 0 }
    if d > float64(len) { return len }
    return int(d)
}

/// IsRegExp (§7.2.6).
public func IsRegExp(_ v: Value) throws -> bool {
    guard case .object(let o) = v else { return false }
    let m = try o.Get(.symbol(value.SymMatch), v)
    if !m.IsUndefined { return m.Truthy }
    return o.Kind == .regexp
}

func indexOf(_ u: [uint16], _ needle: [uint16], _ from: int) -> int {
    if needle.count == 0 { return from <= u.count ? from : -1 }
    var i = from
    while i + needle.count <= u.count {
        if u[i] == needle[0] {
            var k = 1
            while k < needle.count && u[i + k] == needle[k] { k += 1 }
            if k == needle.count { return i }
        }
        i += 1
    }
    return -1
}

// MARK: String (§22.1)

func installString(_ r: object.Realm) {
    let sp = r.StringPrototype
    // String.prototype is itself a String exotic object for "".
    let ctor = r.Constructor("String", 1, prototype: sp) { _, args, nt in
        var s = str.JSString.Empty
        if args.count > 0 {
            if nt == nil, case .symbol(let sym) = args[0] {
                return .string(str.JSString.From(sym.DescriptiveString))
            }
            s = try object.ToString(args[0])
        }
        guard let n = nt else { return .string(s) }
        let proto = try object.GetPrototypeFromConstructor(n, r.StringPrototype)
        return .object(object.StringObject(s, proto: proto))
    }
    sp.DefineData(key("length"), .number(0), writable: false, enumerable: false, configurable: false)
    sp.Kind = .string
    sp.PrimitiveValue = .string(str.JSString.Empty)

    r.Method(ctor, "fromCharCode", 1) { _, args, _ in
        var out: [uint16] = []
        for a in args { out.append(uint16(truncatingIfNeeded: try object.ToUint32(a))) }
        return .string(str.JSString(out))
    }
    r.Method(ctor, "fromCodePoint", 1) { _, args, _ in
        var out: [uint16] = []
        for a in args {
            let d = try object.ToNumber(a)
            if !value.IsIntegral(d) || d < 0 || d > 0x10FFFF {
                throw object.ThrowRangeError("Invalid code point \(object.Describe(a))")
            }
            utf16.Append(&out, uint32(d))
        }
        return .string(str.JSString(out))
    }
    r.Method(ctor, "raw", 1) { _, args, _ in
        let cooked = try object.ToObject(object.Arg(args, 0))
        let raw = try object.ToObject(try cooked.Get(key("raw"), .object(cooked)))
        let n = try object.LengthOfArrayLike(raw)
        var b = str.Builder()
        var i = 0
        while i < n {
            b.Append(try object.ToString(try raw.Get(value.PropertyKey.FromNumber(float64(i)), .object(raw))))
            if i + 1 < n && i + 1 < args.count {
                b.Append(try object.ToString(args[i + 1]))
            }
            i += 1
        }
        return .string(b.Build())
    }

    r.Method(sp, "toString", 0) { thisV, _, _ in return .string(try thisStringValue(thisV, "toString")) }
    r.Method(sp, "valueOf", 0) { thisV, _, _ in return .string(try thisStringValue(thisV, "valueOf")) }

    r.Method(sp, "at", 1) { thisV, args, _ in
        let s = try thisString(thisV, "at")
        let rel = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        let k = rel >= 0 ? rel : float64(s.Length) + rel
        if k < 0 || k >= float64(s.Length) { return .undefined }
        return .string(str.JSString([s.At(int(k))]))
    }
    r.Method(sp, "charAt", 1) { thisV, args, _ in
        let s = try thisString(thisV, "charAt")
        let p = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        if p < 0 || p >= float64(s.Length) { return .string(str.JSString.Empty) }
        return .string(str.JSString([s.At(int(p))]))
    }
    r.Method(sp, "charCodeAt", 1) { thisV, args, _ in
        let s = try thisString(thisV, "charCodeAt")
        let p = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        if p < 0 || p >= float64(s.Length) { return .number(float64.nan) }
        return .number(float64(s.At(int(p))))
    }
    r.Method(sp, "codePointAt", 1) { thisV, args, _ in
        let s = try thisString(thisV, "codePointAt")
        let p = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        if p < 0 || p >= float64(s.Length) { return .undefined }
        return .number(float64(s.CodePointAt(int(p)).cp))
    }
    r.Method(sp, "concat", 1) { thisV, args, _ in
        var s = try thisString(thisV, "concat")
        for a in args { s = s.Concat(try object.ToString(a)) }
        return .string(s)
    }
    func searchMethod(_ name: string, _ body: @escaping ([uint16], [uint16], Value) throws -> Value) {
        r.Method(sp, name, 1) { thisV, args, _ in
            let s = try thisString(thisV, name)
            let search = object.Arg(args, 0)
            if try IsRegExp(search) {
                throw object.ThrowTypeError("First argument to String.prototype.\(name) must not be a regular expression")
            }
            let ss = try object.ToString(search)
            return try body(s.Units, ss.Units, object.Arg(args, 1))
        }
    }
    searchMethod("startsWith") { u, n, pos in
        let start = clampIndex(try object.ToIntegerOrInfinity(pos), u.count)
        if start + n.count > u.count { return .bool(false) }
        var i = 0
        while i < n.count { if u[start + i] != n[i] { return .bool(false) }; i += 1 }
        return .bool(true)
    }
    searchMethod("endsWith") { u, n, pos in
        let end = pos.IsUndefined ? u.count : clampIndex(try object.ToIntegerOrInfinity(pos), u.count)
        let start = end - n.count
        if start < 0 { return .bool(false) }
        var i = 0
        while i < n.count { if u[start + i] != n[i] { return .bool(false) }; i += 1 }
        return .bool(true)
    }
    searchMethod("includes") { u, n, pos in
        let start = clampIndex(try object.ToIntegerOrInfinity(pos), u.count)
        return .bool(indexOf(u, n, start) >= 0)
    }
    r.Method(sp, "indexOf", 1) { thisV, args, _ in
        let u = try thisString(thisV, "indexOf").Units
        let n = try object.ToString(object.Arg(args, 0)).Units
        let start = clampIndex(try object.ToIntegerOrInfinity(object.Arg(args, 1)), u.count)
        return .number(float64(indexOf(u, n, start)))
    }
    r.Method(sp, "lastIndexOf", 1) { thisV, args, _ in
        let u = try thisString(thisV, "lastIndexOf").Units
        let n = try object.ToString(object.Arg(args, 0)).Units
        let numPos = try object.ToNumber(object.Arg(args, 1))
        let pos = numPos.isNaN ? float64.infinity : value.ToIntegerOrInfinity(numPos)
        var start = clampIndex(pos, u.count)
        if start + n.count > u.count { start = u.count - n.count }
        while start >= 0 {
            var k = 0
            while k < n.count && u[start + k] == n[k] { k += 1 }
            if k == n.count { return .number(float64(start)) }
            start -= 1
        }
        return .number(-1)
    }
    r.Method(sp, "slice", 2) { thisV, args, _ in
        let s = try thisString(thisV, "slice")
        let len = s.Length
        let from = relative(try object.ToIntegerOrInfinity(object.Arg(args, 0)), len)
        let to = object.Arg(args, 1).IsUndefined ? len : relative(try object.ToIntegerOrInfinity(args[1]), len)
        if from >= to { return .string(str.JSString.Empty) }
        return .string(s.Slice(from, to))
    }
    r.Method(sp, "substring", 2) { thisV, args, _ in
        let s = try thisString(thisV, "substring")
        let len = s.Length
        let a = clampIndex(try object.ToIntegerOrInfinity(object.Arg(args, 0)), len)
        let b = object.Arg(args, 1).IsUndefined ? len : clampIndex(try object.ToIntegerOrInfinity(args[1]), len)
        return .string(s.Slice(min(a, b), max(a, b)))
    }
    r.Method(sp, "substr", 2) { thisV, args, _ in
        let s = try thisString(thisV, "substr")
        let len = s.Length
        let start = relative(try object.ToIntegerOrInfinity(object.Arg(args, 0)), len)
        let l = object.Arg(args, 1).IsUndefined ? float64(len) : try object.ToIntegerOrInfinity(args[1])
        let end = min(float64(start) + max(l, 0), float64(len))
        if float64(start) >= end { return .string(str.JSString.Empty) }
        return .string(s.Slice(start, int(end)))
    }
    r.Method(sp, "repeat", 1) { thisV, args, _ in
        let s = try thisString(thisV, "repeat")
        let n = try object.ToIntegerOrInfinity(object.Arg(args, 0))
        if n < 0 || n == float64.infinity {
            throw object.ThrowRangeError("Invalid count value: \(value.NumberToString(n))")
        }
        if s.Length == 0 || n == 0 { return .string(str.JSString.Empty) }
        if float64(s.Length) * n > 536870888 { throw object.ThrowRangeError("Invalid string length") }
        var out: [uint16] = []
        let u = s.Units
        var i = 0
        while i < int(n) { out.append(contentsOf: u); i += 1 }
        return .string(str.JSString(out))
    }
    func pad(_ name: string, atStart: bool) {
        r.Method(sp, name, 2) { thisV, args, _ in
            let s = try thisString(thisV, name)
            let maxLen = try object.ToLength(object.Arg(args, 0))
            if maxLen <= float64(s.Length) { return .string(s) }
            var filler: [uint16] = [0x20]
            if !object.Arg(args, 1).IsUndefined { filler = try object.ToString(args[1]).Units }
            if filler.isEmpty { return .string(s) }
            if maxLen > 536870888 { throw object.ThrowRangeError("Invalid string length") }
            let fillLen = int(maxLen) - s.Length
            var fill: [uint16] = []
            fill.reserveCapacity(fillLen)
            while fill.count < fillLen { fill.append(filler[fill.count % filler.count]) }
            let fs = str.JSString(fill)
            return .string(atStart ? fs.Concat(s) : s.Concat(fs))
        }
    }
    pad("padStart", atStart: true)
    pad("padEnd", atStart: false)
    func trim(_ name: string, _ start: bool, _ end: bool) -> object.NativeFunction {
        let f = r.Function(name, 0) { thisV, _, _ in
            let u = try thisString(thisV, name).Units
            var a = 0
            var b = u.count
            if start { while a < b && token.IsSpace(uint32(u[a])) { a += 1 } }
            if end { while b > a && token.IsSpace(uint32(u[b - 1])) { b -= 1 } }
            return .string(units(u, a, b))
        }
        sp.DefineData(key(name), .object(f), writable: true, enumerable: false, configurable: true)
        return f
    }
    _ = trim("trim", true, true)
    let ts = trim("trimStart", true, false)
    let te = trim("trimEnd", false, true)
    sp.DefineData(key("trimLeft"), .object(ts), writable: true, enumerable: false, configurable: true)
    sp.DefineData(key("trimRight"), .object(te), writable: true, enumerable: false, configurable: true)

    func caseMethod(_ name: string, upper: bool) {
        r.Method(sp, name, 0) { thisV, _, _ in
            let u = try thisString(thisV, name).Units
            var ascii = true
            for c in u where c >= 0x80 { ascii = false; break }
            if ascii {
                var out = u
                var i = 0
                while i < out.count {
                    let c = out[i]
                    if upper && c >= 97 && c <= 122 { out[i] = c - 32 }
                    if !upper && c >= 65 && c <= 90 { out[i] = c + 32 }
                    i += 1
                }
                return .string(str.JSString(out))
            }
            let cps = utf16.CodePoints(u)
            let mapped = upper ? unicode.Uppercased(cps) : unicode.Lowercased(cps)
            return .string(str.JSString(utf16.FromCodePoints(mapped)))
        }
    }
    caseMethod("toUpperCase", upper: true)
    caseMethod("toLowerCase", upper: false)
    caseMethod("toLocaleUpperCase", upper: true)
    caseMethod("toLocaleLowerCase", upper: false)

    r.Method(sp, "normalize", 0) { thisV, args, _ in
        let s = try thisString(thisV, "normalize")
        var form = norm.Form.nfc
        let fv = object.Arg(args, 0)
        if !fv.IsUndefined {
            let f = try object.ToString(fv).String
            if f == "NFC" { form = .nfc } else if f == "NFD" { form = .nfd } else if f == "NFKC" { form = .nfkc } else if f == "NFKD" { form = .nfkd } else {
                throw object.ThrowRangeError("The normalization form should be one of NFC, NFD, NFKC, NFKD.")
            }
        }
        let cps = utf16.CodePoints(s.Units)
        return .string(str.JSString(utf16.FromCodePoints(norm.Normalize(cps, form))))
    }
    r.Method(sp, "isWellFormed", 0) { thisV, _, _ in
        let u = try thisString(thisV, "isWellFormed").Units
        var i = 0
        while i < u.count {
            let (cp, w) = utf16.DecodeAt(u, i)
            if cp >= 0xD800 && cp <= 0xDFFF { return .bool(false) }
            i += w
        }
        return .bool(true)
    }
    r.Method(sp, "toWellFormed", 0) { thisV, _, _ in
        var u = try thisString(thisV, "toWellFormed").Units
        var i = 0
        while i < u.count {
            let (cp, w) = utf16.DecodeAt(u, i)
            if cp >= 0xD800 && cp <= 0xDFFF { u[i] = 0xFFFD }
            i += w
        }
        return .string(str.JSString(u))
    }
    r.Method(sp, "localeCompare", 1) { thisV, args, _ in
        let s = try thisString(thisV, "localeCompare")
        let t = try object.ToString(object.Arg(args, 0))
        return .number(float64(LocaleCompare(s, t)))
    }

    // Methods that defer to a RegExp's symbol methods (§22.1.3).
    func regexpMethod(_ name: string, _ sym: value.Symbol, _ length: int, _ fallback: @escaping (str.JSString, Value, [Value]) throws -> Value) {
        r.Method(sp, name, length) { thisV, args, _ in
            if thisV.IsNullish {
                throw object.ThrowTypeError("String.prototype.\(name) called on null or undefined")
            }
            let rx = object.Arg(args, 0)
            if !rx.IsNullish {
                if name == "replaceAll" || name == "matchAll" {
                    if try IsRegExp(rx) {
                        guard case .object(let ro) = rx else { return .undefined }
                        let flags = try ro.Get(key("flags"), rx)
                        try object.RequireObjectCoercible(flags)
                        if !(try object.ToString(flags).Units.contains(103)) {
                            throw object.ThrowTypeError("\(name) must be called with a global RegExp")
                        }
                    }
                }
                let m = try object.GetMethod(rx, .symbol(sym))
                if !m.IsUndefined {
                    var rest: [Value] = [thisV]
                    var i = 1
                    while i < args.count { rest.append(args[i]); i += 1 }
                    return try object.Call(m, rx, rest)
                }
            }
            let s = try object.ToString(thisV)
            return try fallback(s, rx, args)
        }
    }
    regexpMethod("match", value.SymMatch, 1) { s, rx, _ in
        let re = try r.CreateRegExp!(rx.IsUndefined ? str.JSString.Empty : try object.ToString(rx), str.JSString.Empty)
        return try object.Invoke(.object(re), .symbol(value.SymMatch), [.string(s)])
    }
    regexpMethod("matchAll", value.SymMatchAll, 1) { s, rx, _ in
        let re = try r.CreateRegExp!(rx.IsUndefined ? str.JSString.Empty : try object.ToString(rx), str.Name("g"))
        return try object.Invoke(.object(re), .symbol(value.SymMatchAll), [.string(s)])
    }
    regexpMethod("search", value.SymSearch, 1) { s, rx, _ in
        let re = try r.CreateRegExp!(rx.IsUndefined ? str.JSString.Empty : try object.ToString(rx), str.JSString.Empty)
        return try object.Invoke(.object(re), .symbol(value.SymSearch), [.string(s)])
    }
    regexpMethod("replace", value.SymReplace, 2) { s, sv, args in
        return try replaceString(s, sv, object.Arg(args, 1), all: false)
    }
    regexpMethod("replaceAll", value.SymReplace, 2) { s, sv, args in
        return try replaceString(s, sv, object.Arg(args, 1), all: true)
    }
    regexpMethod("split", value.SymSplit, 2) { s, sepV, args in
        let limV = object.Arg(args, 1)
        let lim: uint32 = limV.IsUndefined ? 4294967295 : try object.ToUint32(limV)
        let sep = try object.ToString(sepV)
        if lim == 0 { return .object(object.CreateArrayFromList(r, [])) }
        if sepV.IsUndefined { return .object(object.CreateArrayFromList(r, [.string(s)])) }
        let u = s.Units
        let n = sep.Units
        if n.isEmpty {
            var out: [Value] = []
            for c in u {
                if out.count >= int(lim) { break }
                out.append(.string(str.JSString([c])))
            }
            return .object(object.CreateArrayFromList(r, out))
        }
        if u.isEmpty { return .object(object.CreateArrayFromList(r, [.string(s)])) }
        var out: [Value] = []
        var p = 0
        var q = indexOf(u, n, 0)
        while q >= 0 {
            out.append(.string(units(u, p, q)))
            if out.count >= int(lim) { return .object(object.CreateArrayFromList(r, out)) }
            p = q + n.count
            q = indexOf(u, n, p)
        }
        out.append(.string(units(u, p, u.count)))
        return .object(object.CreateArrayFromList(r, out))
    }

    // Annex B's HTML methods (§B.2.2.2).
    let html: [(string, string, string)] = [
        ("anchor", "a", "name"), ("big", "big", ""), ("blink", "blink", ""), ("bold", "b", ""),
        ("fixed", "tt", ""), ("fontcolor", "font", "color"), ("fontsize", "font", "size"),
        ("italics", "i", ""), ("link", "a", "href"), ("small", "small", ""), ("strike", "strike", ""),
        ("sub", "sub", ""), ("sup", "sup", ""),
    ]
    for (name, tag, attr) in html {
        r.Method(sp, name, attr.isEmpty ? 0 : 1) { thisV, args, _ in
            let s = try thisString(thisV, name)
            var b = str.Builder()
            b.AppendASCII("<" + tag)
            if !attr.isEmpty {
                let v = try object.ToString(object.Arg(args, 0))
                b.AppendASCII(" " + attr + "=\"")
                for c in v.Units {
                    if c == 0x22 { b.AppendASCII("&quot;") } else { b.AppendUnit(c) }
                }
                b.AppendASCII("\"")
            }
            b.AppendASCII(">")
            b.Append(s)
            b.AppendASCII("</" + tag + ">")
            return .string(b.Build())
        }
    }

    installStringIterator(r, sp)
}

func relative(_ d: float64, _ len: int) -> int {
    if d < 0 {
        let x = float64(len) + d
        return x < 0 ? 0 : int(x)
    }
    return d > float64(len) ? len : int(d)
}

/// replaceString is String.prototype.replace and replaceAll with a
/// string pattern (§22.1.3.19, §22.1.3.20).
func replaceString(_ s: str.JSString, _ searchV: Value, _ replaceV: Value, all: bool) throws -> Value {
    let search = try object.ToString(searchV)
    let functional = replaceV.IsCallable
    let replaceStr = functional ? str.JSString.Empty : try object.ToString(replaceV)
    let u = s.Units
    let n = search.Units
    var positions: [int] = []
    var p = indexOf(u, n, 0)
    while p >= 0 {
        positions.append(p)
        if !all { break }
        p = indexOf(u, n, p + max(n.count, 1))
    }
    if positions.isEmpty { return .string(s) }
    var b = str.Builder()
    var end = 0
    for pos in positions {
        b.Append(units(u, end, pos))
        if functional {
            b.Append(try object.ToString(try object.Call(replaceV, .undefined, [.string(search), .number(float64(pos)), .string(s)])))
        } else {
            b.Append(GetSubstitution(search, s, pos, [], nil, replaceStr))
        }
        end = pos + n.count
    }
    b.Append(units(u, end, u.count))
    return .string(b.Build())
}

/// GetSubstitution (§22.1.3.19.1): the replacement template's $
/// patterns. captures are the groups (undefined for unmatched), and
/// namedCaptures the groups object, when the pattern has names.
public func GetSubstitution(_ matched: str.JSString, _ s: str.JSString, _ position: int, _ captures: [Value], _ namedCaptures: object.JSObject?, _ template: str.JSString) -> str.JSString {
    let t = template.Units
    if !t.contains(0x24) { return template }
    let u = s.Units
    let m = captures.count
    let tailPos = min(position + matched.Length, u.count)
    var b = str.Builder()
    var i = 0
    while i < t.count {
        let c = t[i]
        if c != 0x24 || i + 1 >= t.count {
            b.AppendUnit(c)
            i += 1
            continue
        }
        let n = t[i + 1]
        if n == 0x24 {
            b.AppendUnit(0x24)
            i += 2
        } else if n == 0x26 {
            b.Append(matched)
            i += 2
        } else if n == 0x60 {
            b.Append(units(u, 0, min(position, u.count)))
            i += 2
        } else if n == 0x27 {
            b.Append(units(u, tailPos, u.count))
            i += 2
        } else if n >= 0x30 && n <= 0x39 {
            var digits = int(n - 0x30)
            var consumed = 2
            if i + 2 < t.count && t[i + 2] >= 0x30 && t[i + 2] <= 0x39 {
                let two = digits * 10 + int(t[i + 2] - 0x30)
                if two >= 1 && two <= m {
                    digits = two
                    consumed = 3
                }
            }
            if digits >= 1 && digits <= m {
                let cap = captures[digits - 1]
                if case .string(let cs) = cap { b.Append(cs) }
                i += consumed
            } else {
                b.AppendUnit(0x24)
                i += 1
            }
        } else if n == 0x3C, let groups = namedCaptures {
            var close = i + 2
            while close < t.count && t[close] != 0x3E { close += 1 }
            if close >= t.count {
                b.AppendUnit(0x24)
                i += 1
            } else {
                let name = units(t, i + 2, close)
                let v = (try? groups.Get(value.PropertyKey.FromString(name), .object(groups))) ?? .undefined
                if !v.IsUndefined, let vs = try? object.ToString(v) { b.Append(vs) }
                i = close + 1
            }
        } else {
            b.AppendUnit(0x24)
            i += 1
        }
    }
    return b.Build()
}

/// LocaleCompare orders strings roughly as ICU's root collation does for
/// Latin text: letters compared without accents or case first, then
/// accents, then lowercase before uppercase, then code units.
public func LocaleCompare(_ a: str.JSString, _ b: str.JSString) -> int {
    if a.Equals(b) { return 0 }
    let da = norm.Decompose(utf16.CodePoints(a.Units), compat: true)
    let db = norm.Decompose(utf16.CodePoints(b.Units), compat: true)
    func primary(_ cps: [uint32]) -> [uint32] {
        var out: [uint32] = []
        for cp in cps {
            let cat = unicode.Category(cp)
            if cat == .nonspacingMark || cat == .enclosingMark || cat == .spacingMark { continue }
            out.append(unicode.CaseFold(cp))
        }
        return out
    }
    func rank(_ cp: uint32) -> int {
        // Whitespace and punctuation sort before digits, digits before letters.
        if token.IsSpace(cp) { return 0 }
        if unicode.IsLetter(cp) { return 3 }
        if unicode.IsDigit(cp) || unicode.IsNumber(cp) { return 2 }
        return 1
    }
    let pa = primary(da)
    let pb = primary(db)
    var i = 0
    while i < pa.count && i < pb.count {
        if pa[i] != pb[i] {
            let ra = rank(pa[i])
            let rb = rank(pb[i])
            if ra != rb { return ra < rb ? -1 : 1 }
            return pa[i] < pb[i] ? -1 : 1
        }
        i += 1
    }
    if pa.count != pb.count { return pa.count < pb.count ? -1 : 1 }
    // Secondary: accents.
    var ma: [uint32] = []
    var mb: [uint32] = []
    for cp in da where unicode.Category(cp) == .nonspacingMark { ma.append(cp) }
    for cp in db where unicode.Category(cp) == .nonspacingMark { mb.append(cp) }
    if ma != mb {
        if ma.count != mb.count { return ma.count < mb.count ? -1 : 1 }
        i = 0
        while i < ma.count {
            if ma[i] != mb[i] { return ma[i] < mb[i] ? -1 : 1 }
            i += 1
        }
    }
    // Tertiary: lowercase first.
    i = 0
    while i < da.count && i < db.count {
        if da[i] != db[i] {
            let la = unicode.IsLowercase(da[i])
            let lb = unicode.IsLowercase(db[i])
            if la != lb { return la ? -1 : 1 }
            return da[i] < db[i] ? -1 : 1
        }
        i += 1
    }
    return a.Compare(b) < 0 ? -1 : 1
}

// MARK: String Iterator (§22.1.5)

public final class StringIterator: object.JSObject {
    public var Iterated: [uint16]?
    public var Position: int = 0

    public init(_ s: str.JSString, proto: object.JSObject) {
        self.Iterated = s.Units
        super.init(proto: proto)
    }
}

func installStringIterator(_ r: object.Realm, _ sp: object.JSObject) {
    let sip = object.JSObject(proto: r.IteratorPrototype)
    r.Intrinsics["StringIteratorPrototype"] = sip
    r.SymbolMethod(sp, value.SymIterator, 0) { thisV, _, _ in
        let s = try thisString(thisV, "[Symbol.iterator]")
        return .object(StringIterator(s, proto: sip))
    }
    r.Method(sip, "next", 0) { thisV, _, _ in
        guard case .object(let o) = thisV, let it = o as? StringIterator else {
            throw object.ThrowTypeError("Method String Iterator.prototype.next called on incompatible receiver \(object.Describe(thisV))")
        }
        guard let u = it.Iterated else { return .object(object.CreateIterResultObject(.undefined, true)) }
        if it.Position >= u.count {
            it.Iterated = nil
            return .object(object.CreateIterResultObject(.undefined, true))
        }
        let (_, w) = utf16.DecodeAt(u, it.Position)
        let s = units(u, it.Position, it.Position + w)
        it.Position += w
        return .object(object.CreateIterResultObject(.string(s), false))
    }
    sip.DefineData(.symbol(value.SymToStringTag), .string(str.Name("String Iterator")), writable: false, enumerable: false, configurable: true)
}
