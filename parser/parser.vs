// Package parser builds a js/ast tree from source text (ECMA-262 §13–§16).
//
// It is a recursive-descent parser over js/scanner's tokens. Arrow
// parameters and destructuring assignment are parsed first as expressions
// (the spec's cover grammars) and converted to patterns when the "=>" or
// "=" that follows says what they were.
package parser

import (
    "js/ast"
    "js/token"
    "js/scanner"
    "unicode/utf16"
)

/// ParseError is a syntax error: a message, and where.
public enum ParseError: Error, CustomStringConvertible {
    case syntax(message: string, pos: int, line: int)

    public var Message: string {
        switch self {
        case .syntax(let m, _, _): return m
        }
    }

    public var Pos: int {
        switch self {
        case .syntax(_, let p, _): return p
        }
    }

    public var Line: int {
        switch self {
        case .syntax(_, _, let l): return l
        }
    }

    public var description: string {
        return "SyntaxError: \(Message)"
    }
}

/// Options adjusts what a parse accepts.
public struct Options {
    public var Module: bool = false
    public var Strict: bool = false
    /// Function-body contexts, for eval and new Function.
    public var InFunction: bool = false
    public var AllowNewTarget: bool = false
    public var AllowSuperProperty: bool = false
    public var AllowSuperCall: bool = false
    public var AllowArguments: bool = true
    /// PrivateNames are the private names in scope, for eval inside a class.
    public var PrivateNames: [string] = []
    public init() {}
}

/// ParseScript parses a script.
public func ParseScript(_ source: string, filename: string = "") throws -> ast.Program {
    var o = Options()
    o.Module = false
    return try Parse(source, filename: filename, options: o)
}

/// ParseModule parses a module: strict, with import and export.
public func ParseModule(_ source: string, filename: string = "") throws -> ast.Program {
    var o = Options()
    o.Module = true
    o.Strict = true
    return try Parse(source, filename: filename, options: o)
}

/// Parse parses a program with options.
public func Parse(_ source: string, filename: string, options: Options) throws -> ast.Program {
    let p = Parser(source, options: options)
    return try p.ParseProgram(filename: filename)
}

/// ParseFunctionParts parses the parameter list and body text given to
/// the Function constructor, as the spec does: each on its own.
public func ParseFunctionParts(params: string, body: string, isAsync: bool, isGenerator: bool) throws -> ast.FunctionNode {
    let kw = isAsync ? (isGenerator ? "async function*" : "async function") : (isGenerator ? "function*" : "function")
    let source = "(\(kw) anonymous(\(params)\n) {\n\(body)\n})"
    // The parts must parse alone: a body can't close the function early.
    let bp = Parser(body, options: Options())
    bp.inFunction = true
    bp.inAsync = isAsync
    bp.inGenerator = isGenerator
    bp.allowReturn = true
    bp.allowNewTarget = true
    try bp.start()
    while bp.tok.Kind != .eof {
        _ = try bp.parseStatementListItem()
    }
    let p = Parser(source, options: Options())
    try p.start()
    let e = try p.parseExpression()
    if p.tok.Kind != .eof {
        throw p.errorAt("Unexpected token '\(p.tok.Text)'", p.tok)
    }
    if case .paren(let pe) = e, case .function(let f) = pe.Expression {
        f.Name = "anonymous"
        return f
    }
    throw ParseError.syntax(message: "Unexpected token", pos: 0, line: 1)
}

/// Parser holds the state of one parse.
final class Parser {
    let sc: scanner.Scanner
    let options: Options
    var tok: token.Token
    var prevEnd: int = 0
    var prevLine: int = 1

    // Context.
    var strict: bool
    var isModule: bool
    var inFunction: bool = false
    var inAsync: bool = false
    /// inCaseClause is set while a case clause's own statements are parsed.
    var inCaseClause: bool = false
    var inGenerator: bool = false
    var inClassFieldInit: bool = false
    var allowReturn: bool = false
    var allowIn: bool = true
    var allowSuperCall: bool = false
    var allowSuperProperty: bool = false
    var allowNewTarget: bool = false
    var inStaticBlock: bool = false
    var labels: [string] = []
    var iterationDepth: int = 0
    var breakableDepth: int = 0
    /// coverInit holds the positions of {a = 1} shorthands not yet turned
    /// into patterns; one left at the end of a statement is an error.
    var coverInit: [int] = []
    /// awaitPos and yieldPos record the first await or yield seen, so
    /// arrow parameters that contain one can be rejected.
    var privateNames: [[string]] = []

    init(_ source: string, options: Options) {
        self.sc = scanner.Scanner(source)
        self.options = options
        self.strict = options.Strict
        self.isModule = options.Module
        self.tok = token.Token(Kind: .eof)
        self.inFunction = options.InFunction
        self.allowReturn = false
        self.allowNewTarget = options.AllowNewTarget
        self.allowSuperProperty = options.AllowSuperProperty
        self.allowSuperCall = options.AllowSuperCall
        if !options.PrivateNames.isEmpty { privateNames.append(options.PrivateNames) }
    }

    func start() throws {
        try next()
    }

    // MARK: tokens

    func next() throws {
        prevEnd = tok.EndPos
        prevLine = tok.Line
        tok = sc.Next()
        if !sc.Errors.isEmpty {
            throw scanError(sc.Errors[0])
        }
    }

    func scanError(_ e: scanner.ScanError) -> ParseError {
        switch e {
        case .error(let msg, let pos):
            return ParseError.syntax(message: msg, pos: pos, line: lineOf(pos))
        }
    }

    func lineOf(_ pos: int) -> int {
        let b = sc.Bytes
        var line = 1
        var i = 0
        while i < pos && i < b.count {
            if b[i] == 0x0A { line += 1 }
            i += 1
        }
        return line
    }

    func peek() -> token.Token {
        let s = sc.Save()
        let t = sc.Next()
        sc.Restore(s)
        return t
    }

    /// peek2 is the token after the next one.
    func peek2() -> token.Token {
        let s = sc.Save()
        _ = sc.Next()
        let t = sc.Next()
        sc.Restore(s)
        return t
    }

    func at(_ k: token.TokenKind) -> bool { return tok.Kind == k }

    func eat(_ k: token.TokenKind) throws -> bool {
        if tok.Kind == k {
            try next()
            return true
        }
        return false
    }

    func expect(_ k: token.TokenKind) throws {
        if tok.Kind != k {
            throw unexpected()
        }
        try next()
    }

    func errorAt(_ msg: string, _ t: token.Token) -> ParseError {
        return ParseError.syntax(message: msg, pos: t.Pos, line: t.Line)
    }

    func error(_ msg: string, _ pos: int) -> ParseError {
        return ParseError.syntax(message: msg, pos: pos, line: lineOf(pos))
    }

    /// unexpected describes the current token the way V8 does.
    func unexpected() -> ParseError {
        switch tok.Kind {
        case .eof:
            return errorAt("Unexpected end of input", tok)
        case .identifier:
            return errorAt("Unexpected identifier '\(tok.Text)'", tok)
        case .number, .bigint:
            return errorAt("Unexpected number", tok)
        case .string:
            return errorAt("Unexpected string", tok)
        case .templateHead, .templateNoSub, .templateMiddle, .templateTail:
            return errorAt("Unexpected template string", tok)
        case .privateName:
            return errorAt("Unexpected identifier '#\(tok.Text)'", tok)
        default:
            if isReservedWord(tok.Kind) && strict && isStrictReserved(tok.Text) {
                return errorAt("Unexpected strict mode reserved word", tok)
            }
            let text = tok.Text.isEmpty ? sc.Slice(tok.Pos, tok.EndPos) : tok.Text
            return errorAt("Unexpected token '\(text)'", tok)
        }
    }

    func consumeSemicolon() throws {
        if tok.Kind == .semi {
            try next()
            return
        }
        if tok.Kind == .rBrace || tok.Kind == .eof || tok.HasPrecedingLineBreak {
            return
        }
        throw unexpected()
    }

    func isReservedWord(_ k: token.TokenKind) -> bool {
        switch k {
        case .kBreak, .kCase, .kCatch, .kClass, .kConst, .kContinue, .kDebugger, .kDefault,
             .kDelete, .kDo, .kElse, .kExport, .kExtends, .kFinally, .kFor, .kFunction, .kIf,
             .kImport, .kIn, .kInstanceof, .kNew, .kReturn, .kSuper, .kSwitch, .kThis, .kThrow,
             .kTry, .kTypeof, .kVar, .kVoid, .kWhile, .kWith, .kNull, .kTrue, .kFalse:
            return true
        default:
            return false
        }
    }

    func isStrictReserved(_ name: string) -> bool {
        switch name {
        case "implements", "interface", "let", "package", "private", "protected", "public", "static", "yield":
            return true
        default:
            return false
        }
    }

    /// isIdentifier says whether the current token can be an identifier
    /// reference or binding here.
    func isIdentifier(_ t: token.Token) -> bool {
        switch t.Kind {
        case .identifier:
            if strict && isStrictReserved(t.Text) { return false }
            if t.Text == "enum" { return false }
            return true
        case .kAsync, .kOf, .kAs, .kFrom, .kGet, .kSet, .kTarget:
            return true
        case .kLet, .kStatic:
            return !strict
        case .kYield:
            return !strict && !inGenerator
        case .kAwait:
            return !inAsync && !isModule && !inStaticBlock
        default:
            return false
        }
    }

    func parseIdentifierName() throws -> string {
        if tok.Kind == .identifier || tok.IsIdentifierName {
            let name = tok.Text
            try next()
            return name
        }
        throw unexpected()
    }

    func parseBindingIdentifier() throws -> ast.Identifier {
        if !isIdentifier(tok) {
            if tok.Kind == .kYield && (strict || inGenerator) {
                throw errorAt(strict ? "Unexpected strict mode reserved word" : "Yield expression not allowed in formal parameter", tok)
            }
            if tok.Kind == .kAwait {
                throw errorAt("Unexpected reserved word", tok)
            }
            throw unexpected()
        }
        let name = tok.Text
        if strict && (name == "eval" || name == "arguments") {
            throw errorAt("Unexpected eval or arguments in strict mode", tok)
        }
        let id = ast.Identifier(name, at: tok.Pos)
        try next()
        return id
    }

    // MARK: program

    func ParseProgram(filename: string) throws -> ast.Program {
        try start()
        var body: [ast.Stmt] = []
        if options.InFunction {
            allowReturn = false
        }
        try parseDirectives(&body)
        while tok.Kind != .eof {
            let s = try parseStatementListItem()
            body.append(s)
        }
        try checkCoverInit()
        let prog = ast.Program(body: body, isModule: isModule, strict: strict, source: sc.Source, filename: filename)
        return prog
    }

    /// parseDirectives reads a directive prologue ("use strict") into body.
    func parseDirectives(_ body: inout [ast.Stmt]) throws {
        var sawOctal = -1
        while tok.Kind == .string {
            let t = tok
            let raw = sc.Slice(t.Pos, t.EndPos)
            let peekT = peek()
            // A directive is a whole statement: a string followed by ; or
            // the end of the statement.
            if !(peekT.Kind == .semi || peekT.Kind == .rBrace || peekT.Kind == .eof || peekT.HasPrecedingLineBreak) {
                break
            }
            if t.LegacyOctal && sawOctal < 0 { sawOctal = t.Pos }
            let stmt = try parseStatement()
            if case .expr(let es) = stmt { es.Directive = true }
            body.append(stmt)
            if raw == "\"use strict\"" || raw == "'use strict'" {
                strict = true
                if sawOctal >= 0 {
                    throw error("Octal escape sequences are not allowed in strict mode.", sawOctal)
                }
            }
        }
    }

    func checkCoverInit() throws {
        if !coverInit.isEmpty {
            throw error("Invalid shorthand property initializer", coverInit[0])
        }
    }

    // MARK: statements

    func parseStatementListItem() throws -> ast.Stmt {
        // Only a case clause's own statements may not declare using.
        let inCase = inCaseClause
        inCaseClause = false
        switch tok.Kind {
        case .kFunction:
            return .functionDecl(try parseFunction(isAsync: false, isDeclaration: true, start: tok.Pos))
        case .kClass:
            return .classDecl(try parseClass(isDeclaration: true))
        case .kConst:
            return .varDecl(try parseVarDecl(kind: .constKind, requireInit: true))
        case .kLet:
            if isLetDeclaration() {
                return .varDecl(try parseVarDecl(kind: .letKind, requireInit: true))
            }
        case .identifier:
            if !inCase && isUsingDeclaration() {
                return .varDecl(try parseUsingDecl(isAwait: false))
            }
        case .kAwait:
            if !inCase && isAwaitUsingDeclaration() {
                return .varDecl(try parseUsingDecl(isAwait: true))
            }
        case .kAsync:
            let p = peek()
            if p.Kind == .kFunction && !p.HasPrecedingLineBreak && !tok.Escaped {
                let start = tok.Pos
                try next()
                return .functionDecl(try parseFunction(isAsync: true, isDeclaration: true, start: start))
            }
        case .kImport:
            if isModule {
                let p = peek()
                if p.Kind != .lParen && p.Kind != .dot {
                    return try parseImport()
                }
            }
        case .kExport:
            if isModule { return try parseExport() }
            throw errorAt("Unexpected token 'export'", tok)
        default:
            break
        }
        return try parseStatement()
    }

    /// isUsingDeclaration: `using` starts a declaration when a binding
    /// identifier follows on the same line (§14.3.1, ES2026).
    func isUsingDeclaration() -> bool {
        if tok.Kind != .identifier || tok.Escaped || tok.Text != "using" { return false }
        let p = peek()
        return isIdentifier(p) && !p.HasPrecedingLineBreak
    }

    /// isAwaitUsingDeclaration: `await using x`, all on one line, where
    /// await is a keyword.
    func isAwaitUsingDeclaration() -> bool {
        if !(inAsync || (isModule && !inFunction)) { return false }
        let p = peek()
        if p.Kind != .identifier || p.Escaped || p.Text != "using" || p.HasPrecedingLineBreak { return false }
        let p2 = peek2()
        return isIdentifier(p2) && !p2.HasPrecedingLineBreak
    }

    /// parseUsingDecl parses `using` or `await using` declarations: plain
    /// identifiers, each with an initializer.
    func parseUsingDecl(isAwait: bool) throws -> ast.VarDecl {
        let start = tok.Pos
        if isAwait { try next() }
        try next()
        let kind: ast.DeclKind = isAwait ? .awaitUsingKind : .usingKind
        var decls: [ast.Declarator] = []
        while true {
            if tok.Kind == .lBracket || tok.Kind == .lBrace {
                throw error("using declarations may not have binding patterns", tok.Pos)
            }
            let target = try parseBindingTarget()
            if case .identifier(let id) = target, id.Name == "let" {
                throw error("let is disallowed as a lexically bound name", id.At)
            }
            if !(try eat(.assign)) {
                throw error("Missing initializer in \(isAwait ? "await using" : "using") declaration", prevEnd)
            }
            decls.append(ast.Declarator(target: target, initExpr: try parseAssignment()))
            if !(try eat(.comma)) { break }
        }
        try consumeSemicolon()
        return ast.VarDecl(kind: kind, declarations: decls, at: start)
    }

    /// isLetDeclaration: let starts a declaration when an identifier, [ or
    /// { follows.
    func isLetDeclaration() -> bool {
        let p = peek()
        switch p.Kind {
        case .lBracket, .lBrace:
            return true
        case .identifier, .kYield, .kAwait, .kAsync, .kOf, .kAs, .kFrom, .kGet, .kSet, .kTarget, .kStatic, .kLet:
            if p.HasPrecedingLineBreak && !strict {
                // let \n x = 1 is still a declaration.
                return true
            }
            return true
        default:
            return false
        }
    }

    func parseStatement() throws -> ast.Stmt {
        let start = tok.Pos
        switch tok.Kind {
        case .lBrace:
            return .block(try parseBlock())
        case .semi:
            try next()
            return .empty(ast.Pos(start))
        case .kVar:
            return .varDecl(try parseVarDecl(kind: .varKind, requireInit: false))
        case .kIf:
            return try parseIf()
        case .kFor:
            return try parseFor()
        case .kWhile:
            try next()
            try expect(.lParen)
            let test = try parseExpression()
            try expect(.rParen)
            let body = try parseLoopBody()
            return .whileStmt(ast.WhileStmt(test: test, body: body, at: start))
        case .kDo:
            try next()
            let body = try parseLoopBody()
            try expect(.kWhile)
            try expect(.lParen)
            let test = try parseExpression()
            try expect(.rParen)
            // The ; after do-while is optional even without a line break.
            _ = try eat(.semi)
            return .doWhile(ast.WhileStmt(test: test, body: body, at: start))
        case .kContinue, .kBreak:
            let isBreak = tok.Kind == .kBreak
            try next()
            var label: string? = nil
            if !tok.HasPrecedingLineBreak && isIdentifier(tok) {
                label = tok.Text
                if !labels.contains(tok.Text) {
                    throw errorAt("Undefined label '\(tok.Text)'", tok)
                }
                try next()
            } else if isBreak && iterationDepth == 0 && breakableDepth == 0 {
                throw error("Illegal break statement", start)
            } else if !isBreak && iterationDepth == 0 {
                throw error("Illegal continue statement: no surrounding iteration statement", start)
            }
            try consumeSemicolon()
            let j = ast.JumpStmt(label: label, at: start)
            return isBreak ? .breakStmt(j) : .continueStmt(j)
        case .kReturn:
            if !allowReturn {
                throw errorAt("Illegal return statement", tok)
            }
            try next()
            var arg: ast.Expr? = nil
            if tok.Kind != .semi && tok.Kind != .rBrace && tok.Kind != .eof && !tok.HasPrecedingLineBreak {
                arg = try parseExpression()
            }
            try consumeSemicolon()
            return .returnStmt(ast.ReturnStmt(arg, at: start))
        case .kThrow:
            try next()
            if tok.HasPrecedingLineBreak {
                throw error("Illegal newline after throw", prevEnd)
            }
            let arg = try parseExpression()
            try consumeSemicolon()
            return .throwStmt(ast.ThrowStmt(arg, at: start))
        case .kTry:
            return try parseTry()
        case .kSwitch:
            return try parseSwitch()
        case .kWith:
            if strict {
                throw errorAt("Strict mode code may not include a with statement", tok)
            }
            try next()
            try expect(.lParen)
            let obj = try parseExpression()
            try expect(.rParen)
            let body = try parseStatement()
            return .with(ast.WithStmt(object: obj, body: body, at: start))
        case .kDebugger:
            try next()
            try consumeSemicolon()
            return .debugger(ast.Pos(start))
        case .kFunction:
            // Annex B: a function declaration as an if's body, in sloppy mode.
            if strict {
                throw errorAt("In strict mode code, functions can only be declared at top level or inside a block.", tok)
            }
            let f = try parseFunction(isAsync: false, isDeclaration: true, start: tok.Pos)
            return .block(ast.BlockStmt([.functionDecl(f)], at: start))
        case .kClass:
            throw unexpected()
        default:
            break
        }
        // A labeled statement, or an expression statement.
        if isIdentifier(tok) && peek().Kind == .colon {
            let label = tok.Text
            if tok.Kind == .kAwait && (inAsync || isModule) { throw unexpected() }
            try next()
            try next()
            if labels.contains(label) {
                throw error("Label '\(label)' has already been declared", start)
            }
            labels.append(label)
            var body: ast.Stmt
            if tok.Kind == .kFunction {
                if strict { throw errorAt("In strict mode code, functions can only be declared at top level or inside a block.", tok) }
                body = .functionDecl(try parseFunction(isAsync: false, isDeclaration: true, start: tok.Pos))
            } else {
                let savedBreakable = breakableDepth
                breakableDepth += 1
                body = try parseStatement()
                breakableDepth = savedBreakable
            }
            _ = labels.removeLast()
            switch body {
            case .forStmt(let f): f.Labels.insert(label, at: 0)
            case .forIn(let f): f.Labels.insert(label, at: 0)
            case .forOf(let f): f.Labels.insert(label, at: 0)
            case .whileStmt(let w): w.Labels.insert(label, at: 0)
            case .doWhile(let w): w.Labels.insert(label, at: 0)
            case .switchStmt(let s): s.Labels.insert(label, at: 0)
            default: break
            }
            return .labeled(ast.LabeledStmt(label: label, body: body, at: start))
        }
        if tok.Kind == .kLet && peek().Kind == .lBracket {
            throw errorAt("Lexical declaration cannot appear in a single-statement context", tok)
        }
        let e = try parseExpression()
        try consumeSemicolon()
        try checkCoverInit()
        return .expr(ast.ExprStmt(e, at: start))
    }

    func parseLoopBody() throws -> ast.Stmt {
        iterationDepth += 1
        defer { iterationDepth -= 1 }
        return try parseStatement()
    }

    func parseBlock() throws -> ast.BlockStmt {
        let start = tok.Pos
        try expect(.lBrace)
        var body: [ast.Stmt] = []
        while tok.Kind != .rBrace {
            if tok.Kind == .eof { throw unexpected() }
            body.append(try parseStatementListItem())
        }
        try next()
        return ast.BlockStmt(body, at: start)
    }

    func parseVarDecl(kind: ast.DeclKind, requireInit: bool) throws -> ast.VarDecl {
        let start = tok.Pos
        try next()
        let decls = try parseDeclarators(kind: kind, requireInit: requireInit)
        try consumeSemicolon()
        return ast.VarDecl(kind: kind, declarations: decls, at: start)
    }

    func parseDeclarators(kind: ast.DeclKind, requireInit: bool) throws -> [ast.Declarator] {
        var decls: [ast.Declarator] = []
        while true {
            let target = try parseBindingTarget()
            if kind != .varKind, case .identifier(let id) = target, id.Name == "let" {
                throw error("let is disallowed as a lexically bound name", id.At)
            }
            var initExpr: ast.Expr? = nil
            if try eat(.assign) {
                initExpr = try parseAssignment()
            } else if requireInit && kind == .constKind && !(allowIn == false && (tok.Kind == .kIn || tok.Kind == .kOf)) {
                throw error("Missing initializer in const declaration", prevEnd)
            } else if !isIdentPattern(target) && !(allowIn == false && (tok.Kind == .kIn || tok.Kind == .kOf)) {
                throw error("Missing initializer in destructuring declaration", prevEnd)
            }
            decls.append(ast.Declarator(target: target, initExpr: initExpr))
            if !(try eat(.comma)) { break }
        }
        return decls
    }

    func isIdentPattern(_ p: ast.Pattern) -> bool {
        if case .identifier = p { return true }
        return false
    }

    /// parseBindingTarget parses a binding identifier or pattern.
    func parseBindingTarget() throws -> ast.Pattern {
        if tok.Kind == .lBracket {
            return try parseArrayBindingPattern()
        }
        if tok.Kind == .lBrace {
            return try parseObjectBindingPattern()
        }
        return .identifier(try parseBindingIdentifier())
    }

    func parseBindingElement() throws -> ast.PatternElement {
        let target = try parseBindingTarget()
        var def: ast.Expr? = nil
        if try eat(.assign) {
            def = try parseAssignmentAllowIn()
        }
        return ast.PatternElement(target: target, def: def)
    }

    func parseArrayBindingPattern() throws -> ast.Pattern {
        let start = tok.Pos
        try expect(.lBracket)
        var elements: [ast.PatternElement?] = []
        var rest: ast.Pattern? = nil
        while tok.Kind != .rBracket {
            if tok.Kind == .comma {
                try next()
                elements.append(nil)
                continue
            }
            if tok.Kind == .dotDotDot {
                try next()
                rest = try parseBindingTarget()
                if tok.Kind == .comma {
                    throw errorAt("Rest element must be last element", tok)
                }
                break
            }
            elements.append(try parseBindingElement())
            if tok.Kind != .rBracket {
                try expect(.comma)
            }
        }
        try expect(.rBracket)
        return .array(ast.ArrayPattern(elements: elements, rest: rest, at: start))
    }

    func parseObjectBindingPattern() throws -> ast.Pattern {
        let start = tok.Pos
        try expect(.lBrace)
        var props: [ast.PatternProperty] = []
        var rest: ast.Pattern? = nil
        while tok.Kind != .rBrace {
            if tok.Kind == .dotDotDot {
                try next()
                rest = .identifier(try parseBindingIdentifier())
                if tok.Kind == .comma {
                    throw errorAt("Rest element must be last element", tok)
                }
                break
            }
            let keyTok = tok
            let key = try parsePropertyKey()
            if tok.Kind == .colon {
                try next()
                props.append(ast.PatternProperty(key: key, value: try parseBindingElement()))
            } else {
                // Shorthand: the key is the binding.
                guard case .named(let name) = key, keyTok.Kind != .string, keyTok.Kind != .number else {
                    throw unexpected()
                }
                if !isIdentifier(keyTok) {
                    throw errorAt(keyTok.Kind == .identifier ? "Unexpected strict mode reserved word" : "Unexpected token '\(name)'", keyTok)
                }
                if strict && (name == "eval" || name == "arguments") {
                    throw errorAt("Unexpected eval or arguments in strict mode", keyTok)
                }
                var def: ast.Expr? = nil
                if try eat(.assign) {
                    def = try parseAssignmentAllowIn()
                }
                let id = ast.Identifier(name, at: keyTok.Pos)
                props.append(ast.PatternProperty(key: key, value: ast.PatternElement(target: .identifier(id), def: def)))
            }
            if tok.Kind != .rBrace {
                try expect(.comma)
            }
        }
        try expect(.rBrace)
        return .object(ast.ObjectPattern(properties: props, rest: rest, at: start))
    }

    func parseIf() throws -> ast.Stmt {
        let start = tok.Pos
        try next()
        try expect(.lParen)
        let test = try parseExpression()
        try expect(.rParen)
        let cons = try parseStatement()
        var alt: ast.Stmt? = nil
        if try eat(.kElse) {
            alt = try parseStatement()
        }
        return .ifStmt(ast.IfStmt(test: test, consequent: cons, alternate: alt, at: start))
    }

    func parseFor() throws -> ast.Stmt {
        let start = tok.Pos
        try next()
        var isAwait = false
        if tok.Kind == .kAwait {
            if !inAsync && !(isModule && !inFunction) {
                throw unexpected()
            }
            isAwait = true
            try next()
        }
        try expect(.lParen)
        var initStmt: ast.Stmt? = nil

        if tok.Kind == .semi {
            if isAwait { throw unexpected() }
        } else {
            var declKind: ast.DeclKind? = nil
            if tok.Kind == .kVar {
                declKind = .varKind
            } else if tok.Kind == .kConst {
                declKind = .constKind
            } else if tok.Kind == .kLet {
                let p = peek()
                if p.Kind == .lBracket || p.Kind == .lBrace || isIdentifier(p) || p.Kind == .kLet || p.Kind == .kYield || p.Kind == .kAwait {
                    declKind = .letKind
                }
            } else if isUsingDeclaration() && !(peek().Kind == .kOf && peek2().Kind != .assign) {
                declKind = .usingKind
            } else if isAwaitUsingDeclaration() {
                declKind = .awaitUsingKind
            }
            if let kind = declKind {
                let declStart = tok.Pos
                if kind == .awaitUsingKind { try next() }
                try next()
                let savedIn = allowIn
                allowIn = false
                let decls = try parseDeclarators(kind: kind, requireInit: false)
                allowIn = savedIn
                let decl = ast.VarDecl(kind: kind, declarations: decls, at: declStart)
                if tok.Kind == .kOf || (tok.Kind == .kIn && !isAwait) {
                    let isOf = tok.Kind == .kOf
                    if decls.count != 1 {
                        throw error("Invalid left-hand side in for-\(isOf ? "of" : "in") loop: Must have a single binding.", declStart)
                    }
                    if kind.IsUsing && !isOf {
                        throw error("using declarations are not allowed in for-in loops", declStart)
                    }
                    if decls[0].Init != nil {
                        // Annex B allows for (var x = 1 in o) in sloppy mode.
                        if isOf || strict || kind != .varKind || !isIdentPattern(decls[0].Target) {
                            throw error("for-\(isOf ? "of" : "in") loop variable declaration may not have an initializer.", declStart)
                        }
                    }
                    return try parseForInOfRest(decl: decl, target: nil, isOf: isOf, isAwait: isAwait, start: start)
                }
                if isAwait { throw unexpected() }
                for d in decls {
                    if d.Init == nil {
                        if kind == .constKind { throw error("Missing initializer in const declaration", prevEnd) }
                        if kind.IsUsing { throw error("Missing initializer in using declaration", prevEnd) }
                        if !isIdentPattern(d.Target) { throw error("Missing initializer in destructuring declaration", prevEnd) }
                    }
                }
                initStmt = .varDecl(decl)
            } else {
                let exprStart = tok.Pos
                let startsWithLet = tok.Kind == .kLet
                let startsWithAsync = tok.Kind == .kAsync && !tok.Escaped
                let savedIn = allowIn
                allowIn = false
                let e = try parseExpression()
                allowIn = savedIn
                if tok.Kind == .kOf || (tok.Kind == .kIn && !isAwait) {
                    let isOf = tok.Kind == .kOf
                    if isOf && startsWithLet {
                        throw error("The left-hand side of a for-of loop may not be 'let'.", exprStart)
                    }
                    if isOf && startsWithAsync && !isAwait, case .identifier = e {
                        throw error("The left-hand side of a for-of loop may not be 'async'.", exprStart)
                    }
                    let target = try toAssignTarget(e, message: "Invalid left-hand side in for-\(isOf ? "of" : "in") loop")
                    return try parseForInOfRest(decl: nil, target: target, isOf: isOf, isAwait: isAwait, start: start)
                }
                if isAwait { throw unexpected() }
                try checkCoverInit()
                initStmt = .expr(ast.ExprStmt(e, at: exprStart))
            }
        }
        try expect(.semi)
        var test: ast.Expr? = nil
        if tok.Kind != .semi {
            test = try parseExpression()
        }
        try expect(.semi)
        var update: ast.Expr? = nil
        if tok.Kind != .rParen {
            update = try parseExpression()
        }
        try expect(.rParen)
        let body = try parseLoopBody()
        return .forStmt(ast.ForStmt(initStmt: initStmt, test: test, update: update, body: body, at: start))
    }

    func parseForInOfRest(decl: ast.VarDecl?, target: ast.Pattern?, isOf: bool, isAwait: bool, start: int) throws -> ast.Stmt {
        try next()
        let right = isOf ? try parseAssignmentAllowIn() : try parseExpression()
        try expect(.rParen)
        let body = try parseLoopBody()
        let node = ast.ForInStmt(decl: decl, target: target, right: right, body: body, isAwait: isAwait, at: start)
        return isOf ? .forOf(node) : .forIn(node)
    }

    func parseTry() throws -> ast.Stmt {
        let start = tok.Pos
        try next()
        let block = try parseBlock()
        var param: ast.Pattern? = nil
        var handler: ast.BlockStmt? = nil
        var finalizer: ast.BlockStmt? = nil
        if tok.Kind == .kCatch {
            try next()
            if try eat(.lParen) {
                param = try parseBindingTarget()
                try expect(.rParen)
            }
            handler = try parseBlock()
        }
        if tok.Kind == .kFinally {
            try next()
            finalizer = try parseBlock()
        }
        if handler == nil && finalizer == nil {
            throw error("Missing catch or finally after try", prevEnd)
        }
        return .tryStmt(ast.TryStmt(block: block, param: param, handler: handler, finalizer: finalizer, at: start))
    }

    func parseSwitch() throws -> ast.Stmt {
        let start = tok.Pos
        try next()
        try expect(.lParen)
        let disc = try parseExpression()
        try expect(.rParen)
        try expect(.lBrace)
        var cases: [ast.SwitchCase] = []
        var sawDefault = false
        breakableDepth += 1
        while tok.Kind != .rBrace {
            var test: ast.Expr? = nil
            if tok.Kind == .kCase {
                try next()
                test = try parseExpression()
            } else if tok.Kind == .kDefault {
                if sawDefault {
                    throw errorAt("More than one default clause in switch statement", tok)
                }
                sawDefault = true
                try next()
            } else {
                throw unexpected()
            }
            try expect(.colon)
            var body: [ast.Stmt] = []
            while tok.Kind != .kCase && tok.Kind != .kDefault && tok.Kind != .rBrace {
                if tok.Kind == .eof { throw unexpected() }
                // using may not be declared directly in a case clause.
                inCaseClause = true
                body.append(try parseStatementListItem())
            }
            cases.append(ast.SwitchCase(test: test, body: body))
        }
        breakableDepth -= 1
        try next()
        return .switchStmt(ast.SwitchStmt(discriminant: disc, cases: cases, at: start))
    }

    // MARK: modules

    func parseModuleSpecifierString() throws -> string {
        if tok.Kind != .string { throw unexpected() }
        let s = utf16.Decode(tok.Value)
        try next()
        return s
    }

    func parseModuleExportName() throws -> string {
        if tok.Kind == .string {
            let s = utf16.Decode(tok.Value)
            try next()
            return s
        }
        return try parseIdentifierName()
    }

    func parseImport() throws -> ast.Stmt {
        let start = tok.Pos
        try next()
        var specs: [ast.ImportSpecifier] = []
        if tok.Kind == .string {
            let src = try parseModuleSpecifierString()
            try skipImportAttributes()
            try consumeSemicolon()
            return .importDecl(ast.ImportDecl(source: src, specifiers: specs, at: start))
        }
        if isIdentifier(tok) {
            let local = try parseBindingIdentifier()
            specs.append(ast.ImportSpecifier(imported: "default", local: local.Name))
            if !(try eat(.comma)) {
                try expectContextual("from")
                let src = try parseModuleSpecifierString()
                try skipImportAttributes()
                try consumeSemicolon()
                return .importDecl(ast.ImportDecl(source: src, specifiers: specs, at: start))
            }
        }
        if tok.Kind == .mul {
            try next()
            try expectContextual("as")
            let local = try parseBindingIdentifier()
            specs.append(ast.ImportSpecifier(imported: "*", local: local.Name))
        } else if tok.Kind == .lBrace {
            try next()
            while tok.Kind != .rBrace {
                let nameTok = tok
                let imported = try parseModuleExportName()
                var local = imported
                if tok.Kind == .kAs {
                    try next()
                    local = try parseBindingIdentifier().Name
                } else if nameTok.Kind == .string || !isIdentifier(nameTok) {
                    throw errorAt("Unexpected token", nameTok)
                }
                specs.append(ast.ImportSpecifier(imported: imported, local: local))
                if tok.Kind != .rBrace { try expect(.comma) }
            }
            try next()
        } else {
            throw unexpected()
        }
        try expectContextual("from")
        let src = try parseModuleSpecifierString()
        try skipImportAttributes()
        try consumeSemicolon()
        return .importDecl(ast.ImportDecl(source: src, specifiers: specs, at: start))
    }

    func skipImportAttributes() throws {
        if (tok.Kind == .kWith || (tok.Kind == .identifier && tok.Text == "assert")) && !tok.HasPrecedingLineBreak {
            try next()
            try expect(.lBrace)
            while tok.Kind != .rBrace {
                try next()
            }
            try next()
        }
    }

    func expectContextual(_ word: string) throws {
        if tok.Text == word && !tok.Escaped && (tok.Kind == .identifier || tok.Kind == .kAs || tok.Kind == .kFrom || tok.Kind == .kOf) {
            try next()
            return
        }
        throw unexpected()
    }

    func parseExport() throws -> ast.Stmt {
        let start = tok.Pos
        try next()
        let ex = ast.ExportDecl(at: start)
        if tok.Kind == .mul {
            try next()
            ex.IsStar = true
            if tok.Kind == .kAs {
                try next()
                ex.StarAs = try parseModuleExportName()
            }
            try expectContextual("from")
            ex.Source = try parseModuleSpecifierString()
            try skipImportAttributes()
            try consumeSemicolon()
            return .exportDecl(ex)
        }
        if tok.Kind == .kDefault {
            try next()
            if tok.Kind == .kFunction {
                let f = try parseFunction(isAsync: false, isDeclaration: true, start: tok.Pos, allowAnonymous: true)
                if f.Name.isEmpty { f.Name = "default" ; f.IsExpression = true }
                ex.Declaration = .functionDecl(f)
                return .exportDecl(ex)
            }
            if tok.Kind == .kAsync && peek().Kind == .kFunction && !peek().HasPrecedingLineBreak {
                let s = tok.Pos
                try next()
                let f = try parseFunction(isAsync: true, isDeclaration: true, start: s, allowAnonymous: true)
                if f.Name.isEmpty { f.Name = "default" ; f.IsExpression = true }
                ex.Declaration = .functionDecl(f)
                return .exportDecl(ex)
            }
            if tok.Kind == .kClass {
                let c = try parseClass(isDeclaration: true, allowAnonymous: true)
                if c.Name.isEmpty { c.Name = "default" }
                ex.Declaration = .classDecl(c)
                return .exportDecl(ex)
            }
            ex.DefaultExpr = try parseAssignmentAllowIn()
            try consumeSemicolon()
            return .exportDecl(ex)
        }
        if tok.Kind == .lBrace {
            try next()
            var localToks: [token.Token] = []
            while tok.Kind != .rBrace {
                localToks.append(tok)
                let local = try parseModuleExportName()
                var exported = local
                if tok.Kind == .kAs {
                    try next()
                    exported = try parseModuleExportName()
                }
                ex.Specifiers.append(ast.ExportSpecifier(local: local, exported: exported))
                if tok.Kind != .rBrace { try expect(.comma) }
            }
            try next()
            if tok.Kind == .kFrom || (tok.Kind == .identifier && tok.Text == "from") {
                try next()
                ex.Source = try parseModuleSpecifierString()
                try skipImportAttributes()
            } else {
                for t in localToks {
                    if t.Kind == .string || isReservedWord(t.Kind) {
                        throw errorAt("Unexpected token", t)
                    }
                }
            }
            try consumeSemicolon()
            return .exportDecl(ex)
        }
        switch tok.Kind {
        case .kVar:
            ex.Declaration = .varDecl(try parseVarDecl(kind: .varKind, requireInit: false))
        case .kLet:
            ex.Declaration = .varDecl(try parseVarDecl(kind: .letKind, requireInit: true))
        case .kConst:
            ex.Declaration = .varDecl(try parseVarDecl(kind: .constKind, requireInit: true))
        case .kFunction:
            ex.Declaration = .functionDecl(try parseFunction(isAsync: false, isDeclaration: true, start: tok.Pos))
        case .kClass:
            ex.Declaration = .classDecl(try parseClass(isDeclaration: true))
        case .kAsync:
            let s = tok.Pos
            try next()
            ex.Declaration = .functionDecl(try parseFunction(isAsync: true, isDeclaration: true, start: s))
        default:
            throw unexpected()
        }
        return .exportDecl(ex)
    }

    // MARK: functions

    struct FunctionContext {
        var inFunction: bool
        var inAsync: bool
        var inGenerator: bool
        var allowReturn: bool
        var allowSuperCall: bool
        var allowSuperProperty: bool
        var allowNewTarget: bool
        var strict: bool
        var labels: [string]
        var iterationDepth: int
        var breakableDepth: int
        var inClassFieldInit: bool
        var inStaticBlock: bool
    }

    func saveContext() -> FunctionContext {
        return FunctionContext(inFunction: inFunction, inAsync: inAsync, inGenerator: inGenerator, allowReturn: allowReturn,
                               allowSuperCall: allowSuperCall, allowSuperProperty: allowSuperProperty, allowNewTarget: allowNewTarget,
                               strict: strict, labels: labels, iterationDepth: iterationDepth, breakableDepth: breakableDepth,
                               inClassFieldInit: inClassFieldInit, inStaticBlock: inStaticBlock)
    }

    func restoreContext(_ c: FunctionContext) {
        inFunction = c.inFunction
        inAsync = c.inAsync
        inGenerator = c.inGenerator
        allowReturn = c.allowReturn
        allowSuperCall = c.allowSuperCall
        allowSuperProperty = c.allowSuperProperty
        allowNewTarget = c.allowNewTarget
        strict = c.strict
        labels = c.labels
        iterationDepth = c.iterationDepth
        breakableDepth = c.breakableDepth
        inClassFieldInit = c.inClassFieldInit
        inStaticBlock = c.inStaticBlock
    }

    /// parseFunction parses from the function keyword.
    func parseFunction(isAsync: bool, isDeclaration: bool, start: int, allowAnonymous: bool = false) throws -> ast.FunctionNode {
        let line = tok.Line
        try expect(.kFunction)
        let isGen = try eat(.mul)
        var name = ""
        if tok.Kind != .lParen {
            // The name of a function expression is bound inside it, so its
            // yield/await rules are the function's own.
            if isDeclaration {
                let id = try parseBindingIdentifier()
                name = id.Name
            } else {
                let saved = saveContext()
                inGenerator = isGen
                inAsync = isAsync
                let id = try parseBindingIdentifier()
                restoreContext(saved)
                name = id.Name
            }
        } else if isDeclaration && !allowAnonymous {
            throw unexpected()
        }
        let f = try parseFunctionRest(name: name, kind: .normal, isAsync: isAsync, isGenerator: isGen, start: start)
        f.IsExpression = !isDeclaration
        f.Line = line
        return f
    }

    /// parseFunctionRest parses "(params) { body }" into a function node.
    func parseFunctionRest(name: string, kind: ast.FunctionKind, isAsync: bool, isGenerator: bool, start: int) throws -> ast.FunctionNode {
        let saved = saveContext()
        defer { restoreContext(saved) }
        inFunction = true
        inAsync = isAsync
        inGenerator = isGenerator
        allowReturn = true
        allowNewTarget = true
        labels = []
        iterationDepth = 0
        breakableDepth = 0
        inClassFieldInit = false
        inStaticBlock = false
        switch kind {
        case .method, .getter, .setter, .classConstructor, .classFieldInit, .staticBlock:
            allowSuperProperty = true
            allowSuperCall = false
        case .derivedConstructor:
            allowSuperProperty = true
            allowSuperCall = true
        default:
            allowSuperProperty = false
            allowSuperCall = false
        }
        let line = tok.Line
        try expect(.lParen)
        var params: [ast.Param] = []
        var rest: ast.Pattern? = nil
        var simple = true
        while tok.Kind != .rParen {
            if tok.Kind == .dotDotDot {
                try next()
                rest = try parseBindingTarget()
                simple = false
                if tok.Kind == .assign {
                    throw errorAt("Rest parameter may not have a default initializer", tok)
                }
                if tok.Kind != .rParen {
                    throw errorAt("Rest parameter must be last formal parameter", tok)
                }
                break
            }
            let el = try parseBindingElement()
            if el.Default != nil || !isIdentPattern(el.Target) { simple = false }
            params.append(ast.Param(target: el.Target, def: el.Default))
            if tok.Kind != .rParen { try expect(.comma) }
        }
        try next()
        if kind == .getter && (params.count != 0 || rest != nil) {
            throw error("Getter must not have any formal parameters.", start)
        }
        if kind == .setter && (params.count != 1 || rest != nil) {
            throw error("Setter must have exactly one formal parameter.", start)
        }
        let f = ast.FunctionNode(name: name, kind: kind, params: params, rest: rest, body: [], isAsync: isAsync, isGenerator: isGenerator, strict: strict, start: start)
        f.SimpleParams = simple
        f.Line = line
        try parseFunctionBody(f)
        return f
    }

    func parseFunctionBody(_ f: ast.FunctionNode) throws {
        try expect(.lBrace)
        var body: [ast.Stmt] = []
        let wasStrict = strict
        try parseDirectives(&body)
        if strict && !wasStrict {
            if !f.SimpleParams {
                throw error("Illegal 'use strict' directive in function with non-simple parameter list", f.Start)
            }
            try checkStrictParams(f)
        }
        while tok.Kind != .rBrace {
            if tok.Kind == .eof { throw unexpected() }
            body.append(try parseStatementListItem())
        }
        f.End = tok.EndPos
        try next()
        f.Body = body
        f.Strict = strict
        if strict { try checkStrictParams(f) }
    }

    /// checkStrictParams applies strict mode's rules to parameter names.
    func checkStrictParams(_ f: ast.FunctionNode) throws {
        var names: [string] = []
        for p in f.Params { ast.PatternNames(p.Target, &names) }
        if let r = f.Rest { ast.PatternNames(r, &names) }
        var seen: [string: bool] = [:]
        for n in names {
            if n == "eval" || n == "arguments" {
                throw error("Unexpected eval or arguments in strict mode", f.Start)
            }
            if isStrictReserved(n) {
                throw error("Unexpected strict mode reserved word", f.Start)
            }
            if seen[n] != nil {
                throw error("Duplicate parameter name not allowed in this context", f.Start)
            }
            seen[n] = true
        }
        if f.Name == "eval" || f.Name == "arguments" {
            if f.Kind == .normal { throw error("Unexpected eval or arguments in strict mode", f.Start) }
        }
    }

    /// checkParamsUnique rejects duplicate names where they are never allowed.
    func checkParamsUnique(_ f: ast.FunctionNode) throws {
        var names: [string] = []
        for p in f.Params { ast.PatternNames(p.Target, &names) }
        if let r = f.Rest { ast.PatternNames(r, &names) }
        var seen: [string: bool] = [:]
        for n in names {
            if seen[n] != nil {
                throw error("Duplicate parameter name not allowed in this context", f.Start)
            }
            seen[n] = true
        }
    }

    // MARK: classes

    func parseClass(isDeclaration: bool, allowAnonymous: bool = false) throws -> ast.ClassNode {
        let start = tok.Pos
        try expect(.kClass)
        let savedStrict = strict
        strict = true
        defer { strict = savedStrict }
        var name = ""
        if isIdentifier(tok) && tok.Kind != .kExtends {
            name = try parseBindingIdentifier().Name
        } else if tok.Kind == .kYield || tok.Kind == .kLet || tok.Kind == .kStatic || (tok.Kind == .identifier && isStrictReserved(tok.Text)) {
            throw errorAt("Unexpected strict mode reserved word", tok)
        } else if isDeclaration && !allowAnonymous {
            throw unexpected()
        }
        var superClass: ast.Expr? = nil
        if try eat(.kExtends) {
            superClass = try parseLeftHandSide()
        }
        try expect(.lBrace)
        // Collect the class's private names first, so methods can use names
        // declared after them.
        privateNames.append(try scanPrivateNames())
        defer { _ = privateNames.removeLast() }
        let cls = ast.ClassNode(name: name, superClass: superClass, elements: [], at: start)
        cls.Start = start
        var elements: [ast.ClassElement] = []
        var privateKinds: [string: string] = [:]
        while tok.Kind != .rBrace {
            if try eat(.semi) { continue }
            let el = try parseClassElement(cls, derived: superClass != nil)
            if let e = el {
                if case .privateName(let pn) = e.Key {
                    if pn == "constructor" {
                        throw error("Classes may not have a private field named '#constructor'", e.At)
                    }
                    let kind = e.Kind == .getter ? (e.IsStatic ? "sget" : "get") : (e.Kind == .setter ? (e.IsStatic ? "sset" : "set") : "other")
                    if let prev = privateKinds[pn] {
                        let ok = (prev == "get" && kind == "set") || (prev == "set" && kind == "get") || (prev == "sget" && kind == "sset") || (prev == "sset" && kind == "sget")
                        if !ok {
                            throw error("Identifier '#\(pn)' has already been declared", e.At)
                        }
                        privateKinds[pn] = "done"
                    } else {
                        privateKinds[pn] = kind
                    }
                }
                elements.append(e)
            }
        }
        cls.End = tok.EndPos
        try next()
        cls.Elements = elements
        for e in elements {
            e.Value?.Class = cls
        }
        cls.Constructor?.Class = cls
        return cls
    }

    /// scanPrivateNames looks ahead through a class body for #name
    /// declarations, restoring the scanner afterwards.
    func scanPrivateNames() throws -> [string] {
        let s = sc.Save()
        let savedTok = tok
        var names: [string] = []
        var depth = 0
        var t = tok
        var lastWasDot = false
        while t.Kind != .eof {
            if t.Kind == .lBrace || t.Kind == .templateHead { depth += 1 }
            if t.Kind == .rBrace {
                if depth == 0 { break }
                depth -= 1
            }
            if t.Kind == .privateName && depth == 0 && !lastWasDot {
                names.append(t.Text)
            }
            lastWasDot = t.Kind == .dot || t.Kind == .questionDot
            t = sc.Next()
            if !sc.Errors.isEmpty { break }
        }
        sc.Restore(s)
        tok = savedTok
        return names
    }

    func parseClassElement(_ cls: ast.ClassNode, derived: bool) throws -> ast.ClassElement? {
        let start = tok.Pos
        var isStatic = false
        var isAsync = false
        var isGen = false
        var kind: ast.ClassElementKind = .method

        if tok.Kind == .kStatic && !tok.Escaped {
            let p = peek()
            if p.Kind == .lBrace {
                // static { ... }
                try next()
                let f = try parseStaticBlock(start: start)
                return ast.ClassElement(kind: .staticBlock, key: .named(""), isStatic: true, value: f, at: start)
            }
            if p.Kind != .lParen && p.Kind != .assign && p.Kind != .semi && p.Kind != .rBrace && !(p.HasPrecedingLineBreak && isFieldEnd(p)) {
                isStatic = true
                try next()
            }
        }
        if tok.Kind == .kAsync && !tok.Escaped {
            let p = peek()
            if p.Kind != .lParen && p.Kind != .assign && p.Kind != .semi && p.Kind != .rBrace && !p.HasPrecedingLineBreak {
                isAsync = true
                try next()
            }
        }
        if tok.Kind == .mul {
            isGen = true
            try next()
        }
        if !isAsync && !isGen && (tok.Kind == .kGet || tok.Kind == .kSet) && !tok.Escaped {
            let p = peek()
            if p.Kind != .lParen && p.Kind != .assign && p.Kind != .semi && p.Kind != .rBrace && !(p.HasPrecedingLineBreak && isFieldEnd(p)) {
                kind = tok.Kind == .kGet ? .getter : .setter
                try next()
            }
        }
        let keyTok = tok
        let key = try parseClassElementKey()
        var isCtor = false
        if case .named(let n) = key, !isStatic, keyTok.Kind != .lBracket, n == "constructor" {
            isCtor = true
        }
        if case .named(let n) = key, isStatic, keyTok.Kind != .lBracket, n == "prototype" {
            if tok.Kind == .lParen || kind != .method {
                throw errorAt("Classes may not have a static property named 'prototype'", keyTok)
            }
            throw errorAt("Classes may not have a static property named 'prototype'", keyTok)
        }

        if tok.Kind == .lParen {
            if isCtor {
                if kind != .method || isAsync || isGen {
                    throw errorAt("Class constructor may not be a\(kind == .getter ? " getter" : kind == .setter ? " setter" : isAsync ? "n async method" : " generator")", keyTok)
                }
                if cls.Constructor != nil {
                    throw errorAt("A class may only have one constructor", keyTok)
                }
                let f = try parseFunctionRest(name: cls.Name, kind: derived ? .derivedConstructor : .classConstructor, isAsync: false, isGenerator: false, start: cls.Start)
                try checkParamsUnique(f)
                cls.Constructor = f
                return nil
            }
            let fkind: ast.FunctionKind = kind == .getter ? .getter : (kind == .setter ? .setter : .method)
            let f = try parseFunctionRest(name: keyName(key), kind: fkind, isAsync: isAsync, isGenerator: isGen, start: start)
            try checkParamsUnique(f)
            return ast.ClassElement(kind: kind, key: key, isStatic: isStatic, value: f, at: start)
        }
        // A field.
        if kind != .method || isAsync || isGen {
            throw unexpected()
        }
        if isCtor {
            throw errorAt("Classes may not have a field named 'constructor'", keyTok)
        }
        var initFn: ast.FunctionNode? = nil
        if tok.Kind == .assign {
            let initStart = tok.Pos
            try next()
            let saved = saveContext()
            inFunction = true
            inAsync = false
            inGenerator = false
            allowReturn = false
            allowSuperProperty = true
            allowSuperCall = false
            allowNewTarget = true
            inClassFieldInit = true
            inStaticBlock = false
            labels = []
            iterationDepth = 0
            breakableDepth = 0
            let value = try parseAssignmentAllowIn()
            restoreContext(saved)
            let f = ast.FunctionNode(name: keyName(key), kind: .classFieldInit, params: [], rest: nil, body: [], isAsync: false, isGenerator: false, strict: true, start: initStart)
            f.ExprBody = value
            f.End = prevEnd
            initFn = f
        }
        try consumeSemicolon()
        return ast.ClassElement(kind: .field, key: key, isStatic: isStatic, value: initFn, at: start)
    }

    func isFieldEnd(_ t: token.Token) -> bool {
        return true
    }

    func keyName(_ k: ast.PropertyKey) -> string {
        switch k {
        case .named(let n): return n
        case .privateName(let n): return "#" + n
        case .computed: return ""
        }
    }

    func parseClassElementKey() throws -> ast.PropertyKey {
        if tok.Kind == .privateName {
            let n = tok.Text
            try next()
            return .privateName(n)
        }
        return try parsePropertyKey()
    }

    func parseStaticBlock(start: int) throws -> ast.FunctionNode {
        let saved = saveContext()
        defer { restoreContext(saved) }
        inFunction = true
        inAsync = false
        inGenerator = false
        allowReturn = false
        allowSuperProperty = true
        allowSuperCall = false
        allowNewTarget = true
        inStaticBlock = true
        labels = []
        iterationDepth = 0
        breakableDepth = 0
        let f = ast.FunctionNode(name: "", kind: .staticBlock, params: [], rest: nil, body: [], isAsync: false, isGenerator: false, strict: true, start: start)
        let block = try parseBlock()
        f.Body = block.Body
        f.End = prevEnd
        return f
    }

    // MARK: expressions

    func parseExpression() throws -> ast.Expr {
        let start = tok.Pos
        let first = try parseAssignment()
        if tok.Kind != .comma { return first }
        var exprs = [first]
        while try eat(.comma) {
            exprs.append(try parseAssignment())
        }
        return .sequence(ast.SequenceExpr(exprs, at: start))
    }

    func parseAssignmentAllowIn() throws -> ast.Expr {
        let saved = allowIn
        allowIn = true
        defer { allowIn = saved }
        return try parseAssignment()
    }

    func parseExpressionAllowIn() throws -> ast.Expr {
        let saved = allowIn
        allowIn = true
        defer { allowIn = saved }
        return try parseExpression()
    }

    func isAssignOp(_ k: token.TokenKind) -> bool {
        switch k {
        case .assign, .addAssign, .subAssign, .mulAssign, .divAssign, .modAssign, .expAssign,
             .shlAssign, .shrAssign, .ushrAssign, .andAssign, .orAssign, .xorAssign,
             .logicalAndAssign, .logicalOrAssign, .nullishAssign:
            return true
        default:
            return false
        }
    }

    func parseAssignment() throws -> ast.Expr {
        let start = tok.Pos
        // yield
        if tok.Kind == .kYield && inGenerator {
            return try parseYield()
        }
        // Arrow functions: x => ..., async x => ..., async (...) => ...
        if isIdentifier(tok) || tok.Kind == .kYield {
            let p = peek()
            if p.Kind == .arrow && !p.HasPrecedingLineBreak {
                return try parseArrowFromIdentifier(isAsync: false, start: start)
            }
            if tok.Kind == .kAsync && !tok.Escaped && !p.HasPrecedingLineBreak {
                if isIdentifier(p) || p.Kind == .kYield || p.Kind == .kAwait {
                    let p2 = peek2()
                    if p2.Kind == .arrow && !p2.HasPrecedingLineBreak {
                        try next()
                        return try parseArrowFromIdentifier(isAsync: true, start: start)
                    }
                }
            }
        }
        let startTok = tok
        let coverBefore = coverInit.count
        let left = try parseConditional()
        if case .function(let f) = left, f.IsArrow {
            return left
        }
        if isAssignOp(tok.Kind) {
            let op = tok.Kind
            let opTok = tok
            var target: ast.Pattern
            if op == .assign {
                target = try toAssignTarget(left, message: "Invalid left-hand side in assignment")
                // The cover initializers inside became defaults.
                while coverInit.count > coverBefore { _ = coverInit.removeLast() }
            } else {
                target = try toSimpleTarget(left, message: "Invalid left-hand side in assignment")
            }
            _ = opTok
            try next()
            let value = try parseAssignment()
            return .assign(ast.AssignExpr(op: op, target: target, value: value, at: start))
        }
        _ = startTok
        return left
    }

    func parseYield() throws -> ast.Expr {
        let start = tok.Pos
        if inClassFieldInit {
            throw errorAt("Yield expression not allowed in formal parameter", tok)
        }
        try next()
        var delegate = false
        var arg: ast.Expr? = nil
        if !tok.HasPrecedingLineBreak {
            if tok.Kind == .mul {
                delegate = true
                try next()
                arg = try parseAssignment()
            } else {
                switch tok.Kind {
                case .rParen, .rBracket, .rBrace, .comma, .colon, .semi, .eof, .templateMiddle, .templateTail:
                    break
                case .kIn where !allowIn:
                    break
                default:
                    if tok.Kind != .question {
                        arg = try parseAssignment()
                    }
                }
            }
        }
        return .yieldExpr(ast.YieldExpr(argument: arg, delegate: delegate, at: start))
    }

    func parseArrowFromIdentifier(isAsync: bool, start: int) throws -> ast.Expr {
        let saved = saveContext()
        if isAsync { inAsync = true }
        let id = try parseBindingIdentifier()
        restoreContext(saved)
        if isAsync && id.Name == "await" {
            throw error("'await' is not a valid identifier name in an async function", id.At)
        }
        let params = [ast.Param(target: .identifier(id), def: nil)]
        return try parseArrowBody(params: params, rest: nil, isAsync: isAsync, start: start, simple: true)
    }

    /// parseArrowBody parses from "=>".
    func parseArrowBody(params: [ast.Param], rest: ast.Pattern?, isAsync: bool, start: int, simple: bool) throws -> ast.Expr {
        if tok.HasPrecedingLineBreak {
            throw unexpected()
        }
        try expect(.arrow)
        let saved = saveContext()
        defer { restoreContext(saved) }
        inFunction = true
        inAsync = isAsync
        inGenerator = false
        allowReturn = true
        labels = []
        iterationDepth = 0
        breakableDepth = 0
        let line = tok.Line
        let f = ast.FunctionNode(name: "", kind: .arrow, params: params, rest: rest, body: [], isAsync: isAsync, isGenerator: false, strict: strict, start: start)
        f.SimpleParams = simple
        f.Line = line
        try checkParamsUnique(f)
        if tok.Kind == .lBrace {
            try parseFunctionBody(f)
        } else {
            let wasClassField = inClassFieldInit
            _ = wasClassField
            f.ExprBody = try parseAssignment()
            f.End = prevEnd
            if strict { try checkStrictParams(f) }
        }
        f.IsExpression = true
        for p in params {
            var names: [string] = []
            ast.PatternNames(p.Target, &names)
            for n in names where n == "await" && isAsync {
                throw error("'await' is not a valid identifier name in an async function", start)
            }
        }
        return .function(f)
    }

    func parseConditional() throws -> ast.Expr {
        let start = tok.Pos
        let test = try parseBinary(minPrec: 0)
        if tok.Kind != .question { return test }
        if case .function(let f) = test, f.IsArrow { return test }
        try next()
        let cons = try parseAssignmentAllowIn()
        try expect(.colon)
        let alt = try parseAssignment()
        return .conditional(ast.ConditionalExpr(test: test, consequent: cons, alternate: alt, at: start))
    }

    func binaryPrec(_ k: token.TokenKind) -> int {
        switch k {
        case .nullishCoalesce: return 1
        case .logicalOr: return 2
        case .logicalAnd: return 3
        case .bitOr: return 4
        case .bitXor: return 5
        case .bitAnd: return 6
        case .eq, .notEq, .strictEq, .strictNotEq: return 7
        case .less, .lessEq, .greater, .greaterEq, .kInstanceof: return 8
        case .kIn: return allowIn ? 8 : 0
        case .shl, .shr, .ushr: return 9
        case .add, .sub: return 10
        case .mul, .div, .mod: return 11
        case .exp: return 12
        default: return 0
        }
    }

    func parseBinary(minPrec: int) throws -> ast.Expr {
        let start = tok.Pos
        var left: ast.Expr
        // #x in obj
        if tok.Kind == .privateName && peek().Kind == .kIn && allowIn {
            let name = tok.Text
            try checkPrivateName(name, tok)
            try next()
            try next()
            let right = try parseBinary(minPrec: 9)
            left = .privateIn(ast.PrivateInExpr(name: name, right: right, at: start))
        } else {
            left = try parseUnary()
        }
        if case .function(let f) = left, f.IsArrow { return left }
        while true {
            let op = tok.Kind
            let prec = binaryPrec(op)
            if prec == 0 || prec <= minPrec { break }
            if op == .exp {
                if case .unary = left {
                    throw errorAt("Unary operator used immediately before exponentiation expression. Parenthesis must be used to disambiguate operator precedence", tok)
                }
            }
            try next()
            let right: ast.Expr
            if op == .exp {
                right = try parseBinary(minPrec: prec - 1)
            } else {
                right = try parseBinary(minPrec: prec)
            }
            if op == .logicalAnd || op == .logicalOr || op == .nullishCoalesce {
                // ?? can't mix with && or || without parentheses.
                if op == .nullishCoalesce {
                    if case .logical(let l) = left, l.Op != .nullishCoalesce { throw error("Unexpected token '??'", ast.ExprPos(right)) }
                    if case .logical(let r) = right, r.Op != .nullishCoalesce { throw error("Unexpected token '??'", ast.ExprPos(right)) }
                } else {
                    if case .logical(let l) = left, l.Op == .nullishCoalesce { throw error("Unexpected token", ast.ExprPos(right)) }
                    if case .logical(let r) = right, r.Op == .nullishCoalesce { throw error("Unexpected token", ast.ExprPos(right)) }
                }
                left = .logical(ast.LogicalExpr(op: op, left: left, right: right, at: start))
            } else {
                left = .binary(ast.BinaryExpr(op: op, left: left, right: right, at: start))
            }
        }
        return left
    }

    func parseUnary() throws -> ast.Expr {
        let start = tok.Pos
        switch tok.Kind {
        case .logicalNot, .bitNot, .add, .sub, .kTypeof, .kVoid, .kDelete:
            let op = tok.Kind
            try next()
            let arg = try parseUnary()
            if op == .kDelete && strict {
                if case .identifier = ast.StripParens(arg) {
                    throw error("Delete of an unqualified identifier in strict mode.", start)
                }
            }
            if op == .kDelete, case .member(let m) = ast.StripParens(arg), m.Private {
                throw error("Private fields can not be deleted", start)
            }
            return .unary(ast.UnaryExpr(op: op, argument: arg, at: start))
        case .inc, .dec:
            let op = tok.Kind
            try next()
            let arg = try parseUnary()
            _ = try toSimpleTarget(arg, message: "Invalid left-hand side expression in prefix operation")
            return .update(ast.UpdateExpr(op: op, prefix: true, argument: arg, at: start))
        case .kAwait:
            if inAsync || (isModule && !inFunction) {
                if inClassFieldInit && !inAsync {
                    throw unexpected()
                }
                try next()
                let arg = try parseUnary()
                return .awaitExpr(ast.AwaitExpr(arg, at: start))
            }
            if inStaticBlock {
                throw errorAt("Unexpected reserved word", tok)
            }
        default:
            break
        }
        let e = try parseLeftHandSide()
        if (tok.Kind == .inc || tok.Kind == .dec) && !tok.HasPrecedingLineBreak {
            if case .function(let f) = e, f.IsArrow { return e }
            let op = tok.Kind
            _ = try toSimpleTarget(e, message: "Invalid left-hand side expression in postfix operation")
            try next()
            return .update(ast.UpdateExpr(op: op, prefix: false, argument: e, at: start))
        }
        return e
    }

    /// parseLeftHandSide parses member access, calls, new and optional chains.
    func parseLeftHandSide() throws -> ast.Expr {
        let start = tok.Pos
        var e: ast.Expr
        if tok.Kind == .kNew {
            e = try parseNew()
        } else if tok.Kind == .kSuper {
            e = try parseSuper()
        } else if tok.Kind == .kImport {
            e = try parseImportExpr()
        } else {
            e = try parsePrimary()
        }
        if case .function(let f) = e, f.IsArrow { return e }
        var inChain = false
        while true {
            switch tok.Kind {
            case .dot:
                try next()
                if tok.Kind == .privateName {
                    let n = tok.Text
                    try checkPrivateName(n, tok)
                    try next()
                    e = .member(ast.MemberExpr(object: e, name: n, property: nil, computed: false, isPrivate: true, optional: false, at: start))
                } else {
                    let name = try parseIdentifierName()
                    e = .member(ast.MemberExpr(object: e, name: name, property: nil, computed: false, isPrivate: false, optional: false, at: start))
                }
            case .lBracket:
                try next()
                let prop = try parseExpressionAllowIn()
                try expect(.rBracket)
                e = .member(ast.MemberExpr(object: e, name: "", property: prop, computed: true, isPrivate: false, optional: false, at: start))
            case .lParen:
                let args = try parseArguments()
                let call = ast.CallExpr(callee: e, args: args, optional: false, at: start)
                if case .identifier(let id) = e, id.Name == "eval" {
                    call.DirectEval = true
                }
                e = .call(call)
            case .templateNoSub, .templateHead:
                if inChain {
                    throw errorAt("Invalid tagged template on optional chain", tok)
                }
                let quasi = try parseTemplate(tagged: true)
                e = .taggedTemplate(ast.TaggedTemplate(tag: e, quasi: quasi, at: start))
            case .questionDot:
                inChain = true
                try next()
                if tok.Kind == .lParen {
                    let args = try parseArguments()
                    e = .call(ast.CallExpr(callee: e, args: args, optional: true, at: start))
                } else if tok.Kind == .lBracket {
                    try next()
                    let prop = try parseExpressionAllowIn()
                    try expect(.rBracket)
                    e = .member(ast.MemberExpr(object: e, name: "", property: prop, computed: true, isPrivate: false, optional: true, at: start))
                } else if tok.Kind == .privateName {
                    let n = tok.Text
                    try checkPrivateName(n, tok)
                    try next()
                    e = .member(ast.MemberExpr(object: e, name: n, property: nil, computed: false, isPrivate: true, optional: true, at: start))
                } else if tok.Kind == .templateNoSub || tok.Kind == .templateHead {
                    throw errorAt("Invalid tagged template on optional chain", tok)
                } else {
                    let name = try parseIdentifierName()
                    e = .member(ast.MemberExpr(object: e, name: name, property: nil, computed: false, isPrivate: false, optional: true, at: start))
                }
            default:
                if inChain {
                    return .optionalChain(ast.OptionalChain(e, at: start))
                }
                return e
            }
        }
    }

    func parseArguments() throws -> [ast.Expr] {
        try expect(.lParen)
        var args: [ast.Expr] = []
        let savedIn = allowIn
        allowIn = true
        defer { allowIn = savedIn }
        while tok.Kind != .rParen {
            if tok.Kind == .dotDotDot {
                let s = tok.Pos
                try next()
                args.append(.spread(ast.SpreadElement(try parseAssignment(), at: s)))
            } else {
                args.append(try parseAssignment())
            }
            if tok.Kind != .rParen {
                if tok.Kind != .comma {
                    if tok.Kind == .eof { throw unexpected() }
                    throw errorAt("missing ) after argument list", tok)
                }
                try next()
            }
        }
        try next()
        return args
    }

    func parseNew() throws -> ast.Expr {
        let start = tok.Pos
        try next()
        if tok.Kind == .dot {
            try next()
            if tok.Kind == .kTarget && !tok.Escaped {
                if !allowNewTarget && !inFunction {
                    throw error("new.target expression is not allowed here", start)
                }
                try next()
                return .newTarget(ast.NewTargetExpr(at: start))
            }
            throw unexpected()
        }
        var callee: ast.Expr
        if tok.Kind == .kNew {
            callee = try parseNew()
        } else if tok.Kind == .kSuper {
            callee = try parseSuper()
        } else if tok.Kind == .kImport {
            throw errorAt("Cannot use new with import", tok)
        } else {
            callee = try parsePrimary()
        }
        // Member accesses bind tighter than new; the first ( is new's arguments.
        while true {
            if tok.Kind == .dot {
                try next()
                if tok.Kind == .privateName {
                    let n = tok.Text
                    try checkPrivateName(n, tok)
                    try next()
                    callee = .member(ast.MemberExpr(object: callee, name: n, property: nil, computed: false, isPrivate: true, optional: false, at: start))
                } else {
                    let name = try parseIdentifierName()
                    callee = .member(ast.MemberExpr(object: callee, name: name, property: nil, computed: false, isPrivate: false, optional: false, at: start))
                }
            } else if tok.Kind == .lBracket {
                try next()
                let prop = try parseExpressionAllowIn()
                try expect(.rBracket)
                callee = .member(ast.MemberExpr(object: callee, name: "", property: prop, computed: true, isPrivate: false, optional: false, at: start))
            } else if tok.Kind == .templateNoSub || tok.Kind == .templateHead {
                let quasi = try parseTemplate(tagged: true)
                callee = .taggedTemplate(ast.TaggedTemplate(tag: callee, quasi: quasi, at: start))
            } else if tok.Kind == .questionDot {
                throw errorAt("Invalid optional chain from new expression", tok)
            } else {
                break
            }
        }
        var args: [ast.Expr] = []
        if tok.Kind == .lParen {
            args = try parseArguments()
        }
        return .newExpr(ast.NewExpr(callee: callee, args: args, at: start))
    }

    func parseSuper() throws -> ast.Expr {
        let start = tok.Pos
        try next()
        if tok.Kind == .lParen {
            if !allowSuperCall {
                throw error("'super' keyword unexpected here", start)
            }
            let args = try parseArguments()
            return .superCall(ast.SuperCall(args: args, at: start))
        }
        if !allowSuperProperty {
            throw error("'super' keyword unexpected here", start)
        }
        if tok.Kind == .dot {
            try next()
            if tok.Kind == .privateName {
                throw errorAt("Unexpected private field", tok)
            }
            let name = try parseIdentifierName()
            return .superMember(ast.SuperMember(property: .string(ast.StringLit(utf16.Encode(name), at: start)), computed: false, at: start))
        }
        if tok.Kind == .lBracket {
            try next()
            let prop = try parseExpressionAllowIn()
            try expect(.rBracket)
            return .superMember(ast.SuperMember(property: prop, computed: true, at: start))
        }
        throw error("'super' keyword unexpected here", start)
    }

    func parseImportExpr() throws -> ast.Expr {
        let start = tok.Pos
        try next()
        if tok.Kind == .dot {
            try next()
            if tok.Text == "meta" && !tok.Escaped {
                if !isModule {
                    throw error("Cannot use 'import.meta' outside a module", start)
                }
                try next()
                return .importMeta(ast.Pos(start))
            }
            throw unexpected()
        }
        if tok.Kind == .lParen {
            try next()
            let src = try parseAssignmentAllowIn()
            if tok.Kind == .comma {
                try next()
                if tok.Kind != .rParen {
                    _ = try parseAssignmentAllowIn()
                    _ = try eat(.comma)
                }
            }
            try expect(.rParen)
            return .importCall(ast.ImportCall(src, at: start))
        }
        throw unexpected()
    }

    func checkPrivateName(_ name: string, _ t: token.Token) throws {
        for names in privateNames.reversed() {
            if names.contains(name) { return }
        }
        throw errorAt("Private field '#\(name)' must be declared in an enclosing class", t)
    }

    func parsePrimary() throws -> ast.Expr {
        let start = tok.Pos
        switch tok.Kind {
        case .number:
            let v = tok.Number
            if tok.LegacyOctal && strict {
                throw errorAt("Octal literals are not allowed in strict mode.", tok)
            }
            try next()
            return .number(ast.NumberLit(v, at: start))
        case .bigint:
            let d = tok.Text
            try next()
            return .bigint(ast.BigIntLit(d, at: start))
        case .string:
            if tok.LegacyOctal && strict {
                throw errorAt("Octal escape sequences are not allowed in strict mode.", tok)
            }
            let v = tok.Value
            try next()
            return .string(ast.StringLit(v, at: start))
        case .templateNoSub, .templateHead:
            return .template(try parseTemplate(tagged: false))
        case .div, .divAssign:
            let t = sc.RescanRegExp(tok)
            if !sc.Errors.isEmpty { throw scanError(sc.Errors[0]) }
            tok = t
            let pattern = t.Text
            let flags = t.Raw
            try next()
            return .regex(ast.RegExpLit(pattern: pattern, flags: flags, at: start))
        case .kTrue, .kFalse:
            let v = tok.Kind == .kTrue
            try next()
            return .boolean(ast.BoolLit(v, at: start))
        case .kNull:
            try next()
            return .nullLit(ast.Pos(start))
        case .kThis:
            try next()
            return .thisExpr(ast.ThisExpr(at: start))
        case .lParen:
            return try parseParenOrArrow()
        case .lBracket:
            return try parseArrayLiteral()
        case .lBrace:
            return try parseObjectLiteral()
        case .kFunction:
            return .function(try parseFunction(isAsync: false, isDeclaration: false, start: start))
        case .kClass:
            return .classExpr(try parseClass(isDeclaration: false))
        case .kAsync:
            let p = peek()
            if p.Kind == .kFunction && !p.HasPrecedingLineBreak && !tok.Escaped {
                try next()
                return .function(try parseFunction(isAsync: true, isDeclaration: false, start: start))
            }
            if p.Kind == .lParen && !p.HasPrecedingLineBreak && !tok.Escaped {
                return try parseAsyncCallOrArrow()
            }
        default:
            break
        }
        if isIdentifier(tok) {
            let name = tok.Text
            if name == "arguments" && inClassFieldInit {
                throw errorAt("'arguments' is not allowed in class field initializer or static initialization block", tok)
            }
            try next()
            return .identifier(ast.Identifier(name, at: start))
        }
        if tok.Kind == .kAwait && inStaticBlock {
            throw errorAt("Unexpected reserved word", tok)
        }
        if tok.Kind == .kLet && strict {
            throw errorAt("Unexpected strict mode reserved word", tok)
        }
        throw unexpected()
    }

    func parseTemplate(tagged: bool) throws -> ast.TemplateLit {
        let start = tok.Pos
        var cooked: [[uint16]?] = []
        var raw: [string] = []
        var exprs: [ast.Expr] = []
        var t = tok
        while true {
            if t.InvalidEscape {
                if !tagged {
                    throw errorAt("Invalid escape sequence in template", t)
                }
                cooked.append(nil)
            } else {
                cooked.append(t.Value)
            }
            raw.append(t.Raw)
            if t.Kind == .templateNoSub || t.Kind == .templateTail {
                try next()
                break
            }
            try next()
            exprs.append(try parseExpressionAllowIn())
            if tok.Kind != .rBrace {
                throw unexpected()
            }
            t = sc.RescanTemplate(tok)
            if !sc.Errors.isEmpty { throw scanError(sc.Errors[0]) }
            tok = t
        }
        return ast.TemplateLit(cooked: cooked, raw: raw, exprs: exprs, at: start)
    }

    func parseArrayLiteral() throws -> ast.Expr {
        let start = tok.Pos
        try next()
        var elements: [ast.Expr] = []
        let savedIn = allowIn
        allowIn = true
        defer { allowIn = savedIn }
        while tok.Kind != .rBracket {
            if tok.Kind == .comma {
                elements.append(.hole(ast.Pos(tok.Pos)))
                try next()
                continue
            }
            if tok.Kind == .dotDotDot {
                let s = tok.Pos
                try next()
                elements.append(.spread(ast.SpreadElement(try parseAssignment(), at: s)))
                if tok.Kind == .comma && peek().Kind == .rBracket {
                    // A trailing comma after a spread makes it invalid as a rest.
                    trailingCommaAfterSpread.append(start)
                }
            } else {
                elements.append(try parseAssignment())
            }
            if tok.Kind != .rBracket {
                try expect(.comma)
            }
        }
        try next()
        return .array(ast.ArrayLit(elements: elements, at: start))
    }

    var trailingCommaAfterSpread: [int] = []

    /// parsePropertyKey parses a property name: an identifier name, a
    /// string or number, or [computed].
    func parsePropertyKey() throws -> ast.PropertyKey {
        switch tok.Kind {
        case .string:
            let v = tok.Value
            try next()
            return .named(utf16.Decode(v))
        case .number:
            let n = tok.Number
            let at = tok.Pos
            if tok.LegacyOctal && strict {
                throw errorAt("Octal literals are not allowed in strict mode.", tok)
            }
            try next()
            return .computed(.number(ast.NumberLit(n, at: at)))
        case .bigint:
            let d = tok.Text
            let at = tok.Pos
            try next()
            return .computed(.bigint(ast.BigIntLit(d, at: at)))
        case .lBracket:
            try next()
            let e = try parseAssignmentAllowIn()
            try expect(.rBracket)
            return .computed(e)
        case .privateName:
            throw unexpected()
        default:
            if tok.Kind == .identifier || tok.IsIdentifierName {
                let n = tok.Text
                try next()
                return .named(n)
            }
            throw unexpected()
        }
    }

    func parseObjectLiteral() throws -> ast.Expr {
        let start = tok.Pos
        try next()
        var props: [ast.Property] = []
        let savedIn = allowIn
        allowIn = true
        defer { allowIn = savedIn }
        var sawProto = false
        let obj = ast.ObjectLit(properties: [], at: start)
        while tok.Kind != .rBrace {
            let pstart = tok.Pos
            if tok.Kind == .dotDotDot {
                try next()
                let arg = try parseAssignment()
                props.append(ast.Property(kind: .spread, key: .named(""), value: arg, at: pstart))
            } else {
                var isAsync = false
                var isGen = false
                var accessor: ast.PropertyKind? = nil
                if tok.Kind == .kAsync && !tok.Escaped {
                    let p = peek()
                    if p.Kind != .colon && p.Kind != .lParen && p.Kind != .comma && p.Kind != .rBrace && p.Kind != .assign && !p.HasPrecedingLineBreak {
                        isAsync = true
                        try next()
                    }
                }
                if tok.Kind == .mul {
                    isGen = true
                    try next()
                }
                if !isAsync && !isGen && (tok.Kind == .kGet || tok.Kind == .kSet) && !tok.Escaped {
                    let p = peek()
                    if p.Kind != .colon && p.Kind != .lParen && p.Kind != .comma && p.Kind != .rBrace && p.Kind != .assign {
                        accessor = tok.Kind == .kGet ? .getter : .setter
                        try next()
                    }
                }
                let keyTok = tok
                let key = try parsePropertyKey()
                if let acc = accessor {
                    let f = try parseFunctionRest(name: keyName(key), kind: acc == .getter ? .getter : .setter, isAsync: false, isGenerator: false, start: pstart)
                    props.append(ast.Property(kind: acc, key: key, value: .function(f), at: pstart))
                } else if tok.Kind == .lParen {
                    let f = try parseFunctionRest(name: keyName(key), kind: .method, isAsync: isAsync, isGenerator: isGen, start: pstart)
                    try checkParamsUnique(f)
                    props.append(ast.Property(kind: .method, key: key, value: .function(f), at: pstart))
                } else if isAsync || isGen {
                    throw unexpected()
                } else if tok.Kind == .colon {
                    try next()
                    let value = try parseAssignment()
                    var kind = ast.PropertyKind.initProp
                    if case .named(let n) = key, n == "__proto__", keyTok.Kind != .lBracket {
                        if sawProto {
                            throw error("Duplicate __proto__ fields are not allowed in object literals", pstart)
                        }
                        sawProto = true
                        kind = .protoSetter
                    }
                    props.append(ast.Property(kind: kind, key: key, value: value, at: pstart))
                } else {
                    // Shorthand, maybe with a cover initializer: {a} or {a = 1}.
                    guard case .named(let name) = key, keyTok.Kind != .string else {
                        throw unexpected()
                    }
                    if !isIdentifier(keyTok) {
                        if keyTok.Kind == .kAwait && (inAsync || isModule) {
                            throw errorAt("Unexpected reserved word", keyTok)
                        }
                        if strict && isStrictReserved(name) {
                            throw errorAt("Unexpected strict mode reserved word", keyTok)
                        }
                        throw errorAt("Unexpected token '\(name)'", keyTok)
                    }
                    let id = ast.Identifier(name, at: keyTok.Pos)
                    if tok.Kind == .assign {
                        let eqPos = tok.Pos
                        try next()
                        let def = try parseAssignment()
                        coverInit.append(eqPos)
                        obj.CoverInitAt = eqPos
                        let target: ast.Pattern = .identifier(id)
                        props.append(ast.Property(kind: .initProp, key: key, value: .assign(ast.AssignExpr(op: .assign, target: target, value: def, at: keyTok.Pos)), shorthand: true, at: pstart))
                    } else {
                        props.append(ast.Property(kind: .initProp, key: key, value: .identifier(id), shorthand: true, at: pstart))
                    }
                }
            }
            if tok.Kind != .rBrace {
                try expect(.comma)
            }
        }
        try next()
        obj.Properties = props
        return .object(obj)
    }

    /// parseParenOrArrow parses "(" — a parenthesized expression or an
    /// arrow function's parameters.
    func parseParenOrArrow() throws -> ast.Expr {
        let start = tok.Pos
        try next()
        // () => ...
        if tok.Kind == .rParen {
            try next()
            if tok.Kind != .arrow || tok.HasPrecedingLineBreak {
                throw unexpected()
            }
            return try parseArrowBody(params: [], rest: nil, isAsync: false, start: start, simple: true)
        }
        let savedIn = allowIn
        allowIn = true
        var exprs: [ast.Expr] = []
        var rest: ast.Pattern? = nil
        var trailingComma = -1
        let coverBefore = coverInit.count
        while true {
            if tok.Kind == .dotDotDot {
                try next()
                rest = try parseBindingTarget()
                if tok.Kind == .assign {
                    throw errorAt("Rest parameter may not have a default initializer", tok)
                }
                if tok.Kind != .rParen {
                    throw errorAt("Rest parameter must be last formal parameter", tok)
                }
                break
            }
            exprs.append(try parseAssignment())
            if tok.Kind == .comma {
                let commaPos = tok.Pos
                try next()
                if tok.Kind == .rParen {
                    trailingComma = commaPos
                    break
                }
                continue
            }
            break
        }
        allowIn = savedIn
        try expect(.rParen)
        if tok.Kind == .arrow && !tok.HasPrecedingLineBreak {
            var params: [ast.Param] = []
            var simple = rest == nil
            for e in exprs {
                let p = try toParam(e)
                if p.Default != nil || !isIdentPattern(p.Target) { simple = false }
                params.append(p)
            }
            while coverInit.count > coverBefore { _ = coverInit.removeLast() }
            return try parseArrowBody(params: params, rest: rest, isAsync: false, start: start, simple: simple)
        }
        if rest != nil || trailingComma >= 0 {
            throw unexpected()
        }
        let inner: ast.Expr = exprs.count == 1 ? exprs[0] : .sequence(ast.SequenceExpr(exprs, at: ast.ExprPos(exprs[0])))
        return .paren(ast.ParenExpr(inner, at: start))
    }

    /// parseAsyncCallOrArrow parses async( ... ): a call to a function named
    /// async, or an async arrow's parameters.
    func parseAsyncCallOrArrow() throws -> ast.Expr {
        let start = tok.Pos
        let asyncId = ast.Identifier("async", at: start)
        try next()
        try expect(.lParen)
        var args: [ast.Expr] = []
        var rest: ast.Pattern? = nil
        var restExpr: ast.Expr? = nil
        let coverBefore = coverInit.count
        let saved = saveContext()
        while tok.Kind != .rParen {
            if tok.Kind == .dotDotDot {
                let s = tok.Pos
                try next()
                let e = try parseAssignmentAllowIn()
                args.append(.spread(ast.SpreadElement(e, at: s)))
                restExpr = e
                if tok.Kind == .comma {
                    try next()
                    restExpr = nil
                    continue
                }
                break
            }
            args.append(try parseAssignmentAllowIn())
            if tok.Kind != .rParen { try expect(.comma) }
        }
        restoreContext(saved)
        try next()
        if tok.Kind == .arrow && !tok.HasPrecedingLineBreak {
            var params: [ast.Param] = []
            var simple = true
            for a in args {
                if case .spread = a { continue }
                let p = try toParam(a)
                if p.Default != nil || !isIdentPattern(p.Target) { simple = false }
                params.append(p)
            }
            if let r = restExpr {
                rest = try toBindingPattern(r)
                simple = false
            }
            while coverInit.count > coverBefore { _ = coverInit.removeLast() }
            return try parseArrowBody(params: params, rest: rest, isAsync: true, start: start, simple: simple)
        }
        return .call(ast.CallExpr(callee: .identifier(asyncId), args: args, optional: false, at: start))
    }

    // MARK: cover grammar conversions

    /// toParam turns an arrow's parenthesized expression into a parameter.
    func toParam(_ e: ast.Expr) throws -> ast.Param {
        if case .assign(let a) = e, a.Op == .assign {
            let target = try patternToBinding(a.Target)
            if case .yieldExpr = a.Value { throw error("Yield expression not allowed in formal parameter", ast.ExprPos(a.Value)) }
            return ast.Param(target: target, def: a.Value)
        }
        if case .awaitExpr(let aw) = e {
            throw error("Illegal await-expression in formal parameters of async function", aw.At)
        }
        if case .yieldExpr(let y) = e {
            throw error("Yield expression not allowed in formal parameter", y.At)
        }
        return ast.Param(target: try toBindingPattern(e), def: nil)
    }

    /// toBindingPattern turns an expression into a binding pattern: only
    /// identifiers can be bound, not member expressions.
    func toBindingPattern(_ e: ast.Expr) throws -> ast.Pattern {
        let p = try toAssignTarget(e, message: "Invalid destructuring assignment target")
        return try patternToBinding(p)
    }

    func patternToBinding(_ p: ast.Pattern) throws -> ast.Pattern {
        switch p {
        case .identifier(let id):
            if strict && (id.Name == "eval" || id.Name == "arguments") {
                throw error("Unexpected eval or arguments in strict mode", id.At)
            }
            return p
        case .member(let e):
            throw error("Invalid destructuring assignment target", ast.ExprPos(e))
        case .array(let a):
            for el in a.Elements {
                if let x = el { x.Target = try patternToBinding(x.Target) }
            }
            if let r = a.Rest { a.Rest = try patternToBinding(r) }
            return p
        case .object(let o):
            for prop in o.Properties { prop.Value.Target = try patternToBinding(prop.Value.Target) }
            if let r = o.Rest { o.Rest = try patternToBinding(r) }
            return p
        }
    }

    /// toSimpleTarget checks an update or compound assignment's target: an
    /// identifier or a member access.
    func toSimpleTarget(_ e: ast.Expr, message: string) throws -> ast.Pattern {
        switch ast.StripParens(e) {
        case .identifier(let id):
            if strict && (id.Name == "eval" || id.Name == "arguments") {
                throw error("Unexpected eval or arguments in strict mode", id.At)
            }
            return .identifier(id)
        case .member(let m):
            return .member(.member(m))
        case .superMember(let s):
            return .member(.superMember(s))
        case .call(let c):
            // f() = 1 is a runtime ReferenceError in sloppy mode (web compat);
            // we report it early, as V8 does for these forms.
            throw error(message, c.At)
        default:
            throw error(message, ast.ExprPos(e))
        }
    }

    /// toAssignTarget turns an expression into an assignment target,
    /// converting array and object literals into patterns.
    func toAssignTarget(_ e: ast.Expr, message: string) throws -> ast.Pattern {
        switch e {
        case .identifier, .member, .superMember:
            return try toSimpleTarget(e, message: message)
        case .paren(let p):
            switch ast.StripParens(p.Expression) {
            case .identifier, .member, .superMember:
                return try toSimpleTarget(p.Expression, message: message)
            default:
                throw error(message, p.At)
            }
        case .array(let a):
            var elements: [ast.PatternElement?] = []
            var rest: ast.Pattern? = nil
            for i in 0..<a.Elements.count {
                let el = a.Elements[i]
                switch el {
                case .hole:
                    elements.append(nil)
                case .spread(let s):
                    if i != a.Elements.count - 1 || trailingCommaAfterSpread.contains(a.At) {
                        throw error("Rest element must be last element", s.At)
                    }
                    if case .assign = s.Argument {
                        throw error("Invalid destructuring assignment target", s.At)
                    }
                    rest = try toAssignTarget(s.Argument, message: "Invalid destructuring assignment target")
                default:
                    elements.append(try toPatternElement(el))
                }
            }
            return .array(ast.ArrayPattern(elements: elements, rest: rest, at: a.At))
        case .object(let o):
            var props: [ast.PatternProperty] = []
            var rest: ast.Pattern? = nil
            for i in 0..<o.Properties.count {
                let prop = o.Properties[i]
                switch prop.Kind {
                case .initProp, .protoSetter:
                    props.append(ast.PatternProperty(key: prop.Key, value: try toPatternElement(prop.Value)))
                case .spread:
                    if i != o.Properties.count - 1 {
                        throw error("Rest element must be last element", prop.At)
                    }
                    switch prop.Value {
                    case .identifier, .member:
                        rest = try toSimpleTarget(prop.Value, message: "Invalid destructuring assignment target")
                    default:
                        throw error("`...` must be followed by an assignable reference in assignment contexts", prop.At)
                    }
                default:
                    throw error("Invalid destructuring assignment target", prop.At)
                }
            }
            if o.CoverInitAt >= 0 {
                coverInit = coverInit.filter { $0 != o.CoverInitAt }
            }
            return .object(ast.ObjectPattern(properties: props, rest: rest, at: o.At))
        default:
            throw error(message, ast.ExprPos(e))
        }
    }

    func toPatternElement(_ e: ast.Expr) throws -> ast.PatternElement {
        if case .assign(let a) = e, a.Op == .assign {
            // The target was converted when the = was parsed.
            return ast.PatternElement(target: a.Target, def: a.Value)
        }
        return ast.PatternElement(target: try toAssignTarget(e, message: "Invalid destructuring assignment target"), def: nil)
    }
}

