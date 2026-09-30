package text

import (
    "js/object"
    "js/regexp"
    "js/regexp/syntax"
    "js/str"
    "js/value"
)

// RegExp (ECMA-262 §22.2): the constructor, the prototype's methods and
// accessors, the symbol methods String.prototype defers to, and the
// RegExp String Iterator. Matching is js/regexp's.

/// RegExpObject is a RegExp instance: its [[OriginalSource]],
/// [[OriginalFlags]] and [[RegExpMatcher]].
public final class RegExpObject: object.JSObject {
    public var Source: str.JSString = str.JSString.Empty
    public var FlagText: str.JSString = str.JSString.Empty
    public var Program: regexp.Program? = nil

    public override init(proto: object.JSObject?) {
        super.init(proto: proto)
        self.Kind = .regexp
    }
}

let lastIndexKey = value.PropertyKey.Named("lastIndex")

/// programCache keeps compiled patterns: a literal in a loop, or the same
/// pattern built again, compiles once. A program is immutable.
var programCache: [string: regexp.Program] = [:]

func compileProgram(_ source: str.JSString, _ flags: str.JSString) throws -> regexp.Program {
    guard let f = syntax.ParseFlags(flags.Units) else {
        throw object.ThrowSyntaxError("Invalid flags supplied to RegExp constructor '\(flags.String)'")
    }
    let cacheKey = flags.String + "/" + source.String
    if let p = programCache[cacheKey] { return p }
    do {
        let p = try regexp.Program.Compile(source.Units, f)
        if programCache.count >= 512 { programCache = [:] }
        programCache[cacheKey] = p
        return p
    } catch let e as syntax.SyntaxError {
        throw object.ThrowSyntaxError("Invalid regular expression: /\(source.String)/\(flags.String): \(e.Message)")
    }
}

/// regExpAlloc is RegExpAlloc (§22.2.3.2).
func regExpAlloc(_ r: object.Realm, _ newTarget: object.JSObject) throws -> RegExpObject {
    let proto = try object.GetPrototypeFromConstructor(newTarget, r.RegExpPrototype)
    let o = RegExpObject(proto: proto)
    o.DefineData(lastIndexKey, .undefined, writable: true, enumerable: false, configurable: false)
    return o
}

/// regExpInitialize is RegExpInitialize (§22.2.3.3).
func regExpInitialize(_ o: RegExpObject, _ pattern: Value, _ flags: Value) throws -> RegExpObject {
    let p = pattern.IsUndefined ? str.JSString.Empty : try object.ToString(pattern)
    let f = flags.IsUndefined ? str.JSString.Empty : try object.ToString(flags)
    let prog = try compileProgram(p, f)
    o.Source = p
    o.FlagText = f
    o.Program = prog
    try setLastIndex(o, 0)
    return o
}

func setLastIndex(_ o: object.JSObject, _ i: int) throws {
    if !(try o.Set(lastIndexKey, .number(float64(i)), .object(o))) {
        throw object.ThrowTypeError("Cannot assign to read only property 'lastIndex' of object '\(object.Describe(.object(o)))'")
    }
}

func setLastIndexValue(_ o: object.JSObject, _ v: Value) throws {
    if !(try o.Set(lastIndexKey, v, .object(o))) {
        throw object.ThrowTypeError("Cannot assign to read only property 'lastIndex' of object '\(object.Describe(.object(o)))'")
    }
}

func getLastIndex(_ o: object.JSObject) throws -> float64 {
    return try object.ToLength(try o.Get(lastIndexKey, .object(o)))
}

/// thisRegExpObject requires this be an object (for the generic methods).
func thisObject(_ v: Value, _ method: string) throws -> object.JSObject {
    guard case .object(let o) = v else {
        throw object.ThrowTypeError("RegExp.prototype.\(method) called on incompatible receiver \(object.Describe(v))")
    }
    return o
}

/// advanceStringIndex is AdvanceStringIndex (§22.2.7.3).
func advanceStringIndex(_ s: [uint16], _ index: int, _ unicode: bool) -> int {
    if !unicode || index + 1 >= s.count { return index + 1 }
    if s[index] >= 0xD800 && s[index] <= 0xDBFF && s[index + 1] >= 0xDC00 && s[index + 1] <= 0xDFFF {
        return index + 2
    }
    return index + 1
}

// MARK: exec

/// regExpBuiltinExec is RegExpBuiltinExec (§22.2.7.2).
func regExpBuiltinExec(_ r: object.Realm, _ rx: RegExpObject, _ s: str.JSString) throws -> Value {
    let su = s.Units
    var lastIndex = try getLastIndex(rx)
    guard let prog = rx.Program else { throw object.ThrowTypeError("RegExp is not initialized") }
    let fl = prog.Flags
    let globalOrSticky = fl.Global || fl.Sticky
    if !globalOrSticky { lastIndex = 0 }
    if lastIndex > float64(su.count) {
        if globalOrSticky { try setLastIndex(rx, 0) }
        return .null
    }
    guard let caps = prog.Exec(su, int(lastIndex)) else {
        if globalOrSticky { try setLastIndex(rx, 0) }
        return .null
    }
    let start = caps[0]
    let end = caps[1]
    if globalOrSticky { try setLastIndex(rx, end) }
    let n = prog.GroupCount
    var items: [Value] = []
    var g = 0
    while g <= n {
        let a = caps[g * 2]
        let b = caps[g * 2 + 1]
        items.append(a >= 0 && b >= 0 ? .string(units(su, a, b)) : .undefined)
        g += 1
    }
    let arr = object.CreateArrayFromList(r, items)
    arr.DefineData(object.Key("index"), .number(float64(start)))
    arr.DefineData(object.Key("input"), .string(s))
    let names = prog.GroupNames
    var groups: Value = .undefined
    var groupNames: [str.JSString] = []
    var groupIndex: [[int]] = []
    if prog.Pattern.HasNamedGroups {
        var i = 1
        while i <= n {
            if !names[i].isEmpty {
                let nm = str.JSString(names[i])
                var found = -1
                var k = 0
                while k < groupNames.count {
                    if groupNames[k].Equals(nm) { found = k }
                    k += 1
                }
                if found < 0 {
                    groupNames.append(nm)
                    groupIndex.append([i])
                } else {
                    groupIndex[found].append(i)
                }
            }
            i += 1
        }
        let go = object.JSObject(proto: nil)
        var k = 0
        while k < groupNames.count {
            var v: Value = .undefined
            for gi in groupIndex[k] where !items[gi].IsUndefined { v = items[gi] }
            go.DefineData(value.PropertyKey.FromString(groupNames[k]), v)
            k += 1
        }
        groups = .object(go)
    }
    arr.DefineData(object.Key("groups"), groups)
    if fl.HasIndices {
        var pairs: [Value] = []
        var i = 0
        while i <= n {
            let a = caps[i * 2]
            let b = caps[i * 2 + 1]
            if a >= 0 && b >= 0 {
                pairs.append(.object(object.CreateArrayFromList(r, [.number(float64(a)), .number(float64(b))])))
            } else {
                pairs.append(.undefined)
            }
            i += 1
        }
        let indices = object.CreateArrayFromList(r, pairs)
        var ig: Value = .undefined
        if prog.Pattern.HasNamedGroups {
            let go = object.JSObject(proto: nil)
            var k = 0
            while k < groupNames.count {
                var v: Value = .undefined
                for gi in groupIndex[k] where !pairs[gi].IsUndefined { v = pairs[gi] }
                go.DefineData(value.PropertyKey.FromString(groupNames[k]), v)
                k += 1
            }
            ig = .object(go)
        }
        indices.DefineData(object.Key("groups"), ig)
        arr.DefineData(object.Key("indices"), .object(indices))
    }
    return .object(arr)
}

/// regExpExec is RegExpExec (§22.2.7.1): a user exec if there is one.
func regExpExec(_ r: object.Realm, _ rx: object.JSObject, _ s: str.JSString) throws -> Value {
    let exec = try rx.Get(object.Key("exec"), .object(rx))
    if exec.IsCallable {
        if let bo = rx as? RegExpObject, case .object(let eo) = exec, eo === r.Intrinsics["RegExpProtoExec"] {
            return try regExpBuiltinExec(r, bo, s)
        }
        let result = try object.Call(exec, .object(rx), [.string(s)])
        if !result.IsObject && !result.IsNull {
            throw object.ThrowTypeError("exec result must be an object or null")
        }
        return result
    }
    guard let bo = rx as? RegExpObject else {
        throw object.ThrowTypeError("RegExp exec method called on an incompatible receiver")
    }
    return try regExpBuiltinExec(r, bo, s)
}

func getString(_ o: Value, _ k: string) throws -> str.JSString {
    guard case .object(let obj) = o else { return str.JSString.Empty }
    return try object.ToString(try obj.Get(object.Key(k), o))
}

func flagsContain(_ f: str.JSString, _ c: uint16) -> bool {
    return f.Units.contains(c)
}

// MARK: source

/// escapePattern is EscapeRegExpPattern (§22.2.6.13.1): the source as it
/// would be written in a literal.
func escapePattern(_ s: str.JSString) -> str.JSString {
    let u = s.Units
    if u.isEmpty { return str.Name("(?:)") }
    var b = str.Builder()
    var inClass = false
    var i = 0
    while i < u.count {
        let c = u[i]
        if c == 0x5C {
            b.AppendUnit(c)
            if i + 1 < u.count {
                i += 1
                appendEscapedLineTerminator(&b, u[i], escaped: true)
            }
            i += 1
            continue
        }
        if c == 0x5B { inClass = true } else if c == 0x5D { inClass = false }
        if c == 0x2F && !inClass {
            b.AppendUnit(0x5C)
            b.AppendUnit(c)
        } else {
            appendEscapedLineTerminator(&b, c, escaped: false)
        }
        i += 1
    }
    return b.Build()
}

func appendEscapedLineTerminator(_ b: inout str.Builder, _ c: uint16, escaped: bool) {
    let pre = escaped ? "" : "\\"
    switch c {
    case 0x0A: b.Append(str.JSString.From(pre + "n"))
    case 0x0D: b.Append(str.JSString.From(pre + "r"))
    case 0x2028: b.Append(str.JSString.From(pre + "u2028"))
    case 0x2029: b.Append(str.JSString.From(pre + "u2029"))
    default: b.AppendUnit(c)
    }
}

// MARK: RegExp.escape (ES2025)

func regExpEscape(_ s: str.JSString) -> str.JSString {
    let u = s.Units
    var b = str.Builder()
    var i = 0
    while i < u.count {
        var cp = uint32(u[i])
        var width = 1
        if cp >= 0xD800 && cp <= 0xDBFF && i + 1 < u.count && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF {
            cp = 0x10000 + ((cp - 0xD800) << 10) + (uint32(u[i + 1]) - 0xDC00)
            width = 2
        }
        let isDigit = cp >= 0x30 && cp <= 0x39
        let isLetter = (cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A)
        if i == 0 && (isDigit || isLetter) {
            b.Append(str.JSString.From("\\x" + hex2(cp)))
        } else {
            encodeForRegExpEscape(&b, cp, u, i, width)
        }
        i += width
    }
    return b.Build()
}

func hex2(_ v: uint32) -> string {
    let digits = [uint8]("0123456789abcdef".utf8)
    return string(decoding: [digits[int((v >> 4) & 0xF)], digits[int(v & 0xF)]], as: UTF8.self)
}

func hex4(_ v: uint32) -> string {
    return hex2(v >> 8) + hex2(v & 0xFF)
}

func encodeForRegExpEscape(_ b: inout str.Builder, _ c: uint32, _ u: [uint16], _ i: int, _ width: int) {
    let syntaxChars: [uint32] = [0x5E, 0x24, 0x5C, 0x2E, 0x2A, 0x2B, 0x3F, 0x28, 0x29, 0x5B, 0x5D, 0x7B, 0x7D, 0x7C, 0x2F]
    if syntaxChars.contains(c) {
        b.AppendUnit(0x5C)
        b.AppendUnit(uint16(c))
        return
    }
    switch c {
    case 0x09: b.Append(str.Name("\\t")); return
    case 0x0A: b.Append(str.Name("\\n")); return
    case 0x0B: b.Append(str.Name("\\v")); return
    case 0x0C: b.Append(str.Name("\\f")); return
    case 0x0D: b.Append(str.Name("\\r")); return
    default: break
    }
    let others: [uint32] = [0x2C, 0x2D, 0x3D, 0x3C, 0x3E, 0x23, 0x26, 0x21, 0x25, 0x3A, 0x3B, 0x40, 0x7E, 0x27, 0x60, 0x22]
    let isSpace = c == 0x20 || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000 || c == 0xFEFF
    let lone = c >= 0xD800 && c <= 0xDFFF
    if others.contains(c) || isSpace || lone {
        if c <= 0xFF {
            b.Append(str.JSString.From("\\x" + hex2(c)))
        } else {
            b.Append(str.JSString.From("\\u" + hex4(c)))
        }
        return
    }
    var k = 0
    while k < width {
        b.AppendUnit(u[i + k])
        k += 1
    }
}

// MARK: installation

func installRegExp(_ r: object.Realm) {
    let rp = r.RegExpPrototype
    var ctorRef: object.JSObject? = nil
    let ctor = r.Constructor("RegExp", 2, prototype: rp) { _, args, nt in
        let pattern = object.Arg(args, 0)
        let flags = object.Arg(args, 1)
        let patternIsRegExp = try IsRegExp(pattern)
        var newTarget: object.JSObject
        if let n = nt {
            newTarget = n
        } else {
            newTarget = ctorRef!
            if patternIsRegExp && flags.IsUndefined, case .object(let po) = pattern {
                let pc = try po.Get(object.Key("constructor"), pattern)
                if case .object(let pco) = pc, pco === newTarget { return pattern }
            }
        }
        var p = pattern
        var f = flags
        if case .object(let po) = pattern, let ro = po as? RegExpObject {
            p = .string(ro.Source)
            if flags.IsUndefined { f = .string(ro.FlagText) }
        } else if patternIsRegExp, case .object(let po) = pattern {
            p = try po.Get(object.Key("source"), pattern)
            if flags.IsUndefined { f = try po.Get(object.Key("flags"), pattern) }
        }
        let o = try regExpAlloc(r, newTarget)
        return .object(try regExpInitialize(o, p, f))
    }
    ctorRef = ctor
    r.Intrinsics["RegExp"] = ctor
    r.Getter(ctor, .symbol(value.SymSpecies)) { thisV, _, _ in return thisV }
    r.Method(ctor, "escape", 1) { _, args, _ in
        guard case .string(let s) = object.Arg(args, 0) else {
            throw object.ThrowTypeError("RegExp.escape requires a string")
        }
        return .string(regExpEscape(s))
    }

    r.CreateRegExp = { p, f in
        let o = try regExpAlloc(r, ctor)
        return try regExpInitialize(o, .string(p), .string(f))
    }

    // exec, test, toString, compile.
    let exec = r.Function("exec", 1) { thisV, args, _ in
        guard case .object(let o) = thisV, let rx = o as? RegExpObject else {
            throw object.ThrowTypeError("RegExp.prototype.exec called on incompatible receiver \(object.Describe(thisV))")
        }
        return try regExpBuiltinExec(r, rx, try object.ToString(object.Arg(args, 0)))
    }
    rp.DefineData(object.Key("exec"), .object(exec), writable: true, enumerable: false, configurable: true)
    r.Intrinsics["RegExpProtoExec"] = exec
    r.Method(rp, "test", 1) { thisV, args, _ in
        let o = try thisObject(thisV, "test")
        let s = try object.ToString(object.Arg(args, 0))
        return .bool(!(try regExpExec(r, o, s)).IsNull)
    }
    r.Method(rp, "toString", 0) { thisV, _, _ in
        let o = try thisObject(thisV, "toString")
        let src = try object.ToString(try o.Get(object.Key("source"), thisV))
        let fl = try object.ToString(try o.Get(object.Key("flags"), thisV))
        return .string(str.JSString.From("/" + src.String + "/" + fl.String))
    }
    r.Method(rp, "compile", 2) { thisV, args, _ in
        guard case .object(let o) = thisV, let rx = o as? RegExpObject else {
            throw object.ThrowTypeError("RegExp.prototype.compile called on incompatible receiver")
        }
        var p = object.Arg(args, 0)
        var f = object.Arg(args, 1)
        if case .object(let po) = p, let pr = po as? RegExpObject {
            if !f.IsUndefined { throw object.ThrowTypeError("Cannot supply flags when constructing one RegExp from another") }
            p = .string(pr.Source)
            f = .string(pr.FlagText)
        }
        return .object(try regExpInitialize(rx, p, f))
    }

    // The accessors.
    r.Getter(rp, object.Key("source")) { thisV, _, _ in
        guard case .object(let o) = thisV else {
            throw object.ThrowTypeError("RegExp.prototype.source getter called on non-object \(object.Describe(thisV))")
        }
        guard let rx = o as? RegExpObject else {
            if o === rp { return .string(str.Name("(?:)")) }
            throw object.ThrowTypeError("RegExp.prototype.source getter called on non-RegExp object")
        }
        return .string(escapePattern(rx.Source))
    }
    r.Getter(rp, object.Key("flags")) { thisV, _, _ in
        guard case .object(let o) = thisV else {
            throw object.ThrowTypeError("RegExp.prototype.flags getter called on non-object \(object.Describe(thisV))")
        }
        var out: [uint16] = []
        let order: [(string, uint16)] = [("hasIndices", 0x64), ("global", 0x67), ("ignoreCase", 0x69), ("multiline", 0x6D), ("dotAll", 0x73), ("unicode", 0x75), ("unicodeSets", 0x76), ("sticky", 0x79)]
        for (name, ch) in order {
            if try o.Get(object.Key(name), thisV).Truthy { out.append(ch) }
        }
        return .string(str.JSString(out))
    }
    func flagGetter(_ name: string, _ pick: @escaping (syntax.Flags) -> bool) {
        r.Getter(rp, object.Key(name)) { thisV, _, _ in
            guard case .object(let o) = thisV else {
                throw object.ThrowTypeError("RegExp.prototype.\(name) getter called on non-object \(object.Describe(thisV))")
            }
            guard let rx = o as? RegExpObject, let prog = rx.Program else {
                if o === rp { return .undefined }
                throw object.ThrowTypeError("RegExp.prototype.\(name) getter called on non-RegExp object")
            }
            return .bool(pick(prog.Flags))
        }
    }
    flagGetter("dotAll") { $0.DotAll }
    flagGetter("global") { $0.Global }
    flagGetter("hasIndices") { $0.HasIndices }
    flagGetter("ignoreCase") { $0.IgnoreCase }
    flagGetter("multiline") { $0.Multiline }
    flagGetter("sticky") { $0.Sticky }
    flagGetter("unicode") { $0.Unicode }
    flagGetter("unicodeSets") { $0.UnicodeSets }

    // [Symbol.match] (§22.2.6.8)
    r.SymbolMethod(rp, value.SymMatch, 1) { thisV, args, _ in
        let rx = try thisObject(thisV, "[Symbol.match]")
        let s = try object.ToString(object.Arg(args, 0))
        let flags = try getString(thisV, "flags")
        if !flagsContain(flags, 0x67) { return try regExpExec(r, rx, s) }
        let fullUnicode = flagsContain(flags, 0x75) || flagsContain(flags, 0x76)
        try setLastIndex(rx, 0)
        var found: [Value] = []
        while true {
            let result = try regExpExec(r, rx, s)
            if result.IsNull {
                return found.isEmpty ? .null : .object(object.CreateArrayFromList(r, found))
            }
            let matched = try getString(result, "0")
            found.append(.string(matched))
            if matched.IsEmpty {
                let thisIndex = try getLastIndex(rx)
                try setLastIndex(rx, advanceStringIndex(s.Units, int(thisIndex), fullUnicode))
            }
        }
    }

    // [Symbol.matchAll] (§22.2.6.9)
    let rsip = object.JSObject(proto: r.IteratorPrototype)
    r.Intrinsics["RegExpStringIteratorPrototype"] = rsip
    r.SymbolMethod(rp, value.SymMatchAll, 1) { thisV, args, _ in
        let rx = try thisObject(thisV, "[Symbol.matchAll]")
        let s = try object.ToString(object.Arg(args, 0))
        let c = try object.SpeciesConstructor(rx, ctor)
        let flags = try getString(thisV, "flags")
        guard case .object(let matcher) = try object.Construct(c, [thisV, .string(flags)]) else {
            throw object.ThrowTypeError("matchAll: species constructor made no object")
        }
        let lastIndex = try getLastIndex(rx)
        try setLastIndexValue(matcher, .number(lastIndex))
        let it = RegExpStringIterator(proto: rsip)
        it.Matcher = matcher
        it.Str = s
        it.Global = flagsContain(flags, 0x67)
        it.FullUnicode = flagsContain(flags, 0x75) || flagsContain(flags, 0x76)
        return .object(it)
    }
    r.Method(rsip, "next", 0) { thisV, _, _ in
        guard case .object(let o) = thisV, let it = o as? RegExpStringIterator else {
            throw object.ThrowTypeError("Method RegExp String Iterator.prototype.next called on incompatible receiver \(object.Describe(thisV))")
        }
        if it.Done { return .object(object.CreateIterResultObject(.undefined, true)) }
        let m = try regExpExec(r, it.Matcher!, it.Str)
        if m.IsNull {
            it.Done = true
            return .object(object.CreateIterResultObject(.undefined, true))
        }
        if it.Global {
            let matched = try getString(m, "0")
            if matched.IsEmpty {
                let thisIndex = try getLastIndex(it.Matcher!)
                try setLastIndex(it.Matcher!, advanceStringIndex(it.Str.Units, int(thisIndex), it.FullUnicode))
            }
            return .object(object.CreateIterResultObject(m, false))
        }
        it.Done = true
        return .object(object.CreateIterResultObject(m, false))
    }
    rsip.DefineData(.symbol(value.SymToStringTag), .string(str.Name("RegExp String Iterator")), writable: false, enumerable: false, configurable: true)

    // [Symbol.replace] (§22.2.6.11)
    r.SymbolMethod(rp, value.SymReplace, 2) { thisV, args, _ in
        let rx = try thisObject(thisV, "[Symbol.replace]")
        let s = try object.ToString(object.Arg(args, 0))
        let su = s.Units
        let lengthS = su.count
        var replaceValue = object.Arg(args, 1)
        let functional = replaceValue.IsCallable
        if !functional { replaceValue = .string(try object.ToString(replaceValue)) }
        let flags = try getString(thisV, "flags")
        let global = flagsContain(flags, 0x67)
        var fullUnicode = false
        if global {
            fullUnicode = flagsContain(flags, 0x75) || flagsContain(flags, 0x76)
            try setLastIndex(rx, 0)
        }
        var results: [Value] = []
        while true {
            let result = try regExpExec(r, rx, s)
            if result.IsNull { break }
            results.append(result)
            if !global { break }
            let matched = try getString(result, "0")
            if matched.IsEmpty {
                let thisIndex = try getLastIndex(rx)
                try setLastIndex(rx, advanceStringIndex(su, int(thisIndex), fullUnicode))
            }
        }
        var acc = str.Builder()
        var nextSource = 0
        for result in results {
            guard case .object(let ro) = result else { continue }
            let nCaptures = max(try object.LengthOfArrayLike(ro) - 1, 0)
            let matched = try object.ToString(try ro.Get(object.Key("0"), result))
            let matchLength = matched.Length
            let posD = try object.ToIntegerOrInfinity(try ro.Get(object.Key("index"), result))
            let position = posD < 0 ? 0 : (posD > float64(lengthS) ? lengthS : int(posD))
            var captures: [Value] = []
            var k = 1
            while k <= nCaptures {
                let cv = try ro.Get(value.PropertyKey.FromNumber(float64(k)), result)
                captures.append(cv.IsUndefined ? .undefined : .string(try object.ToString(cv)))
                k += 1
            }
            let namedCaptures = try ro.Get(object.Key("groups"), result)
            var replacement: str.JSString
            if functional {
                var fargs: [Value] = [.string(matched)]
                fargs.append(contentsOf: captures)
                fargs.append(.number(float64(position)))
                fargs.append(.string(s))
                if !namedCaptures.IsUndefined { fargs.append(namedCaptures) }
                replacement = try object.ToString(try object.Call(replaceValue, .undefined, fargs))
            } else {
                var groups: object.JSObject? = nil
                if !namedCaptures.IsUndefined { groups = try object.ToObject(namedCaptures) }
                guard case .string(let tmpl) = replaceValue else { continue }
                replacement = GetSubstitution(matched, s, position, captures, groups, tmpl)
            }
            if position >= nextSource {
                acc.Append(units(su, nextSource, position))
                acc.Append(replacement)
                nextSource = position + matchLength
            }
        }
        if nextSource < lengthS { acc.Append(units(su, nextSource, lengthS)) }
        return .string(acc.Build())
    }

    // [Symbol.search] (§22.2.6.12)
    r.SymbolMethod(rp, value.SymSearch, 1) { thisV, args, _ in
        let rx = try thisObject(thisV, "[Symbol.search]")
        let s = try object.ToString(object.Arg(args, 0))
        let previous = try rx.Get(lastIndexKey, thisV)
        if !object.SameValue(previous, .number(0)) { try setLastIndex(rx, 0) }
        let result = try regExpExec(r, rx, s)
        let current = try rx.Get(lastIndexKey, thisV)
        if !object.SameValue(current, previous) { try setLastIndexValue(rx, previous) }
        if result.IsNull { return .number(-1) }
        guard case .object(let ro) = result else { return .number(-1) }
        return try ro.Get(object.Key("index"), result)
    }

    // [Symbol.split] (§22.2.6.14)
    r.SymbolMethod(rp, value.SymSplit, 2) { thisV, args, _ in
        let rx = try thisObject(thisV, "[Symbol.split]")
        let s = try object.ToString(object.Arg(args, 0))
        let su = s.Units
        let c = try object.SpeciesConstructor(rx, ctor)
        let flags = try getString(thisV, "flags")
        let unicodeMatching = flagsContain(flags, 0x75) || flagsContain(flags, 0x76)
        let newFlags = flagsContain(flags, 0x79) ? flags : str.JSString.From(flags.String + "y")
        guard case .object(let splitter) = try object.Construct(c, [thisV, .string(newFlags)]) else {
            throw object.ThrowTypeError("split: species constructor made no object")
        }
        var out: [Value] = []
        let limV = object.Arg(args, 1)
        let lim: uint32 = limV.IsUndefined ? 4294967295 : try object.ToUint32(limV)
        if lim == 0 { return .object(object.CreateArrayFromList(r, [])) }
        let size = su.count
        if size == 0 {
            let z = try regExpExec(r, splitter, s)
            if !z.IsNull { return .object(object.CreateArrayFromList(r, [])) }
            return .object(object.CreateArrayFromList(r, [.string(s)]))
        }
        var p = 0
        var q = p
        while q < size {
            try setLastIndex(splitter, q)
            let z = try regExpExec(r, splitter, s)
            if z.IsNull {
                q = advanceStringIndex(su, q, unicodeMatching)
                continue
            }
            let eD = try getLastIndex(splitter)
            let e = eD > float64(size) ? size : int(eD)
            if e == p {
                q = advanceStringIndex(su, q, unicodeMatching)
                continue
            }
            out.append(.string(units(su, p, q)))
            if out.count == int(lim) { return .object(object.CreateArrayFromList(r, out)) }
            p = e
            guard case .object(let zo) = z else { break }
            let nCaptures = max(try object.LengthOfArrayLike(zo) - 1, 0)
            var i = 1
            while i <= nCaptures {
                out.append(try zo.Get(value.PropertyKey.FromNumber(float64(i)), z))
                if out.count == int(lim) { return .object(object.CreateArrayFromList(r, out)) }
                i += 1
            }
            q = p
        }
        out.append(.string(units(su, p, size)))
        return .object(object.CreateArrayFromList(r, out))
    }
}

/// RegExpStringIterator is what matchAll returns (§22.2.9).
final class RegExpStringIterator: object.JSObject {
    var Matcher: object.JSObject? = nil
    var Str: str.JSString = str.JSString.Empty
    var Global: bool = false
    var FullUnicode: bool = false
    var Done: bool = false
}
