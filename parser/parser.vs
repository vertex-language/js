package parser

import (
    "js/token"
    "js/ast"
    "js/scanner"
)

/// ParseError describes a syntax error with source coordinates.
public struct ParseError: Error, CustomStringConvertible {
    public let Message: string
    public let Pos: int
    public let Line: int
    public let Column: int
    public let Filename: string

    public init(_ message: string, pos: int = 0, line: int = 1, column: int = 1, filename: string = "") {
        self.Message = message
        self.Pos = pos
        self.Line = line
        self.Column = column
        self.Filename = filename
    }

    public var description: string {
        if Filename.isEmpty {
            return "SyntaxError: \(Message) at \(Line):\(Column)"
        }
        return "SyntaxError: \(Message) at \(Filename):\(Line):\(Column)"
    }
}

/// ParseScript parses an entire JavaScript source text as a script.
public func ParseScript(_ source: string, filename: string = "") throws -> ast.Program {
    let p = Parser(source: source, filename: filename)
    return try p.ParseProgram(sourceType: "script")
}

/// ParseModule parses JavaScript source text as an ES module.
public func ParseModule(_ source: string, filename: string = "") throws -> ast.Program {
    let p = Parser(source: source, filename: filename)
    return try p.ParseProgram(sourceType: "module")
}

/// ParseExpr parses a single JavaScript expression.
public func ParseExpr(_ source: string, filename: string = "") throws -> ast.Expr {
    let p = Parser(source: source, filename: filename)
    let e = try p.parseExpression()
    try p.expect(.eof)
    return e
}

/// Parser performs recursive-descent parsing with operator precedence.
public final class Parser {
    let sc: scanner.Scanner
    var current: token.Token
    var previous: token.Token

    public init(source: string, filename: string = "") {
        self.sc = scanner.Scanner(source: source, filename: filename)
        self.previous = token.Token(Kind: .eof)
        self.current = sc.Next()
    }

    func advance() {
        previous = current
        current = sc.Next()
    }

    func check(_ kind: token.TokenKind) -> bool {
        return current.Kind == kind
    }

    func match(_ kind: token.TokenKind) -> bool {
        if check(kind) {
            advance()
            return true
        }
        return false
    }

    func expect(_ kind: token.TokenKind) throws {
        if !match(kind) {
            throw error("expected token \(kind), got \(current.Kind) ('\(current.Text)')")
        }
    }

    func parseIdentifierName() throws -> string {
        if current.IsIdentifierName {
            let name = current.Text
            advance()
            return name
        }
        throw error("expected identifier name, got \(current.Kind) ('\(current.Text)')")
    }

    func parseBindingIdentifier() throws -> string {
        if current.Kind == .identifier || current.IsContextualKeyword {
            let name = current.Text
            advance()
            return name
        }
        throw error("expected binding identifier, got \(current.Kind) ('\(current.Text)')")
    }

    func error(_ msg: string) -> ParseError {
        let loc = sc.File.PositionAt(offset: current.Pos)
        return ParseError(msg, pos: current.Pos, line: loc.Line, column: loc.Column, filename: sc.File.Filename)
    }

    func consumeSemicolon() throws {
        if match(.semi) {
            return
        }
        // Automatic Semicolon Insertion (ASI)
        if current.HasPrecedingLineBreak || check(.rBrace) || check(.eof) {
            return
        }
        throw error("expected ';' or line break")
    }

    public func ParseProgram(sourceType: string = "script") throws -> ast.Program {
        var stmts: [ast.Stmt] = []
        let startPos = current.Pos
        while !check(.eof) {
            let s = try parseStatementListItem()
            stmts.append(s)
        }
        return ast.Program(sourceType: sourceType, body: stmts, pos: startPos)
    }

    func parseStatementListItem() throws -> ast.Stmt {
        if check(.kFunction) {
            return try parseFunctionDeclaration()
        }
        if check(.kVar) || check(.kLet) || check(.kConst) {
            return try parseVariableStatement()
        }
        return try parseStatement()
    }

    func parseStatement() throws -> ast.Stmt {
        switch current.Kind {
        case .semi:
            let pos = current.Pos
            advance()
            return .empty(ast.EmptyStmt(pos: pos))
        case .lBrace:
            return try parseBlockStatement()
        case .kIf:
            return try parseIfStatement()
        case .kWhile:
            return try parseWhileStatement()
        case .kDo:
            return try parseDoWhileStatement()
        case .kFor:
            return try parseForStatement()
        case .kSwitch:
            return try parseSwitchStatement()
        case .kReturn:
            return try parseReturnStatement()
        case .kBreak:
            return try parseBreakStatement()
        case .kContinue:
            return try parseContinueStatement()
        case .kThrow:
            return try parseThrowStatement()
        case .kTry:
            return try parseTryStatement()
        case .kDebugger:
            advance()
            try consumeSemicolon()
            return .empty(ast.EmptyStmt(pos: previous.Pos))
        default:
            return try parseExpressionStatement()
        }
    }

    func parseBlockStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.lBrace)
        var stmts: [ast.Stmt] = []
        while !check(.rBrace) && !check(.eof) {
            let s = try parseStatementListItem()
            stmts.append(s)
        }
        try expect(.rBrace)
        return .block(ast.BlockStmt(statements: stmts, pos: pos))
    }

    func parseVariableStatement() throws -> ast.Stmt {
        let pos = current.Pos
        let kind = current.Text
        advance() // consume var/let/const
        var decls: [ast.VariableDeclarator] = []
        while true {
            let declPos = current.Pos
            let name = try parseBindingIdentifier()
            var initExpr: ast.Expr? = nil
            if match(.assign) {
                initExpr = try parseAssignmentExpression()
            }
            decls.append(ast.VariableDeclarator(Id: name, Init: initExpr, Pos: declPos))
            if !match(.comma) {
                break
            }
        }
        try consumeSemicolon()
        return .varDecl(ast.VarDecl(kind: kind, declarations: decls, pos: pos))
    }

    func parseFunctionDeclaration() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kFunction)
        var isGenerator = false
        if match(.mul) {
            isGenerator = true
        }
        let name = try parseBindingIdentifier()
        try expect(.lParen)
        var params: [string] = []
        if !check(.rParen) {
            while true {
                params.append(try parseBindingIdentifier())
                if !match(.comma) { break }
            }
        }
        try expect(.rParen)
        guard case .block(let body) = try parseBlockStatement() else {
            throw error("expected function block body")
        }
        return .functionDecl(ast.FunctionDecl(name: name, params: params, body: body, isAsync: false, isGenerator: isGenerator, pos: pos))
    }

    func parseIfStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kIf)
        try expect(.lParen)
        let test = try parseExpression()
        try expect(.rParen)
        let cons = try parseStatement()
        var alt: ast.Stmt? = nil
        if match(.kElse) {
            alt = try parseStatement()
        }
        return .ifStmt(ast.IfStmt(test: test, consequent: cons, alternate: alt, pos: pos))
    }

    func parseWhileStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kWhile)
        try expect(.lParen)
        let test = try parseExpression()
        try expect(.rParen)
        let body = try parseStatement()
        return .whileStmt(ast.WhileStmt(test: test, body: body, pos: pos))
    }

    func parseDoWhileStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kDo)
        let body = try parseStatement()
        try expect(.kWhile)
        try expect(.lParen)
        let test = try parseExpression()
        try expect(.rParen)
        try consumeSemicolon()
        return .doWhileStmt(ast.DoWhileStmt(body: body, test: test, pos: pos))
    }

    func parseForStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kFor)
        try expect(.lParen)

        // For-in or for-of or standard for loop
        if match(.semi) {
            // for (; ...)
            let test = check(.semi) ? nil : try parseExpression()
            try expect(.semi)
            let update = check(.rParen) ? nil : try parseExpression()
            try expect(.rParen)
            let body = try parseStatement()
            return .forStmt(ast.ForStmt(initStmt: nil, initExpr: nil, test: test, update: update, body: body, pos: pos))
        }

        if check(.kVar) || check(.kLet) || check(.kConst) {
            let declPos = current.Pos
            let kind = current.Text
            advance()
            let id = current.Text
            try expect(.identifier)

            if match(.kIn) {
                let right = try parseExpression()
                try expect(.rParen)
                let body = try parseStatement()
                let vDecl = ast.VarDecl(kind: kind, declarations: [ast.VariableDeclarator(Id: id, Pos: declPos)], pos: declPos)
                return .forInStmt(ast.ForInStmt(leftVar: vDecl, right: right, body: body, pos: pos))
            }
            if match(.kOf) {
                let right = try parseExpression()
                try expect(.rParen)
                let body = try parseStatement()
                let vDecl = ast.VarDecl(kind: kind, declarations: [ast.VariableDeclarator(Id: id, Pos: declPos)], pos: declPos)
                return .forOfStmt(ast.ForOfStmt(leftVar: vDecl, right: right, body: body, isAwait: false, pos: pos))
            }

            var decls = [ast.VariableDeclarator(Id: id, Pos: declPos)]
            if match(.assign) {
                let initExpr = try parseAssignmentExpression()
                decls[0].Init = initExpr
            }
            while match(.comma) {
                let dPos = current.Pos
                let dName = current.Text
                try expect(.identifier)
                var dInit: ast.Expr? = nil
                if match(.assign) {
                    dInit = try parseAssignmentExpression()
                }
                decls.append(ast.VariableDeclarator(Id: dName, Init: dInit, Pos: dPos))
            }
            try expect(.semi)
            let test = check(.semi) ? nil : try parseExpression()
            try expect(.semi)
            let update = check(.rParen) ? nil : try parseExpression()
            try expect(.rParen)
            let body = try parseStatement()
            let initStmt = ast.Stmt.varDecl(ast.VarDecl(kind: kind, declarations: decls, pos: declPos))
            return .forStmt(ast.ForStmt(initStmt: initStmt, initExpr: nil, test: test, update: update, body: body, pos: pos))
        }

        let initExpr = try parseExpression()
        if match(.semi) {
            let test = check(.semi) ? nil : try parseExpression()
            try expect(.semi)
            let update = check(.rParen) ? nil : try parseExpression()
            try expect(.rParen)
            let body = try parseStatement()
            return .forStmt(ast.ForStmt(initStmt: nil, initExpr: initExpr, test: test, update: update, body: body, pos: pos))
        }

        if match(.kIn) {
            let right = try parseExpression()
            try expect(.rParen)
            let body = try parseStatement()
            return .forInStmt(ast.ForInStmt(leftExpr: initExpr, right: right, body: body, pos: pos))
        }
        if match(.kOf) {
            let right = try parseExpression()
            try expect(.rParen)
            let body = try parseStatement()
            return .forOfStmt(ast.ForOfStmt(leftExpr: initExpr, right: right, body: body, isAwait: false, pos: pos))
        }

        throw error("malformed for loop header")
    }

    func parseSwitchStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kSwitch)
        try expect(.lParen)
        let disc = try parseExpression()
        try expect(.rParen)
        try expect(.lBrace)
        var cases: [ast.SwitchCase] = []
        while !check(.rBrace) && !check(.eof) {
            let casePos = current.Pos
            var test: ast.Expr? = nil
            if match(.kCase) {
                test = try parseExpression()
                try expect(.colon)
            } else if match(.kDefault) {
                try expect(.colon)
            } else {
                throw error("expected case or default")
            }
            var stmts: [ast.Stmt] = []
            while !check(.kCase) && !check(.kDefault) && !check(.rBrace) && !check(.eof) {
                let s = try parseStatementListItem()
                stmts.append(s)
            }
            cases.append(ast.SwitchCase(Test: test, Consequent: stmts, Pos: casePos))
        }
        try expect(.rBrace)
        return .switchStmt(ast.SwitchStmt(discriminant: disc, cases: cases, pos: pos))
    }

    func parseReturnStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kReturn)
        var arg: ast.Expr? = nil
        if !current.HasPrecedingLineBreak && !check(.semi) && !check(.rBrace) && !check(.eof) {
            arg = try parseExpression()
        }
        try consumeSemicolon()
        return .returnStmt(ast.ReturnStmt(arg, pos: pos))
    }

    func parseBreakStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kBreak)
        var label: string? = nil
        if !current.HasPrecedingLineBreak && check(.identifier) {
            label = current.Text
            advance()
        }
        try consumeSemicolon()
        return .breakStmt(ast.BreakStmt(label: label, pos: pos))
    }

    func parseContinueStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kContinue)
        var label: string? = nil
        if !current.HasPrecedingLineBreak && check(.identifier) {
            label = current.Text
            advance()
        }
        try consumeSemicolon()
        return .continueStmt(ast.ContinueStmt(label: label, pos: pos))
    }

    func parseThrowStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kThrow)
        if current.HasPrecedingLineBreak {
            throw error("illegal newline after throw")
        }
        let arg = try parseExpression()
        try consumeSemicolon()
        return .throwStmt(ast.ThrowStmt(arg, pos: pos))
    }

    func parseTryStatement() throws -> ast.Stmt {
        let pos = current.Pos
        try expect(.kTry)
        guard case .block(let block) = try parseBlockStatement() else {
            throw error("expected block in try")
        }
        var handler: ast.CatchClause? = nil
        if match(.kCatch) {
            let catchPos = previous.Pos
            var param: string? = nil
            if match(.lParen) {
                param = current.Text
                try expect(.identifier)
                try expect(.rParen)
            }
            guard case .block(let cBlock) = try parseBlockStatement() else {
                throw error("expected block in catch")
            }
            handler = ast.CatchClause(Param: param, Body: cBlock, Pos: catchPos)
        }
        var finalizer: ast.BlockStmt? = nil
        if match(.kFinally) {
            guard case .block(let fBlock) = try parseBlockStatement() else {
                throw error("expected block in finally")
            }
            finalizer = fBlock
        }
        if handler == nil && finalizer == nil {
            throw error("try requires catch or finally")
        }
        return .tryStmt(ast.TryStmt(block: block, handler: handler, finalizer: finalizer, pos: pos))
    }

    func parseExpressionStatement() throws -> ast.Stmt {
        let pos = current.Pos
        let expr = try parseExpression()
        try consumeSemicolon()
        return .expr(ast.ExprStmt(expr, pos: pos))
    }

    // MARK: - Expressions

    func parseExpression() throws -> ast.Expr {
        let left = try parseAssignmentExpression()
        if !check(.comma) {
            return left
        }
        var exprs = [left]
        let pos = current.Pos
        while match(.comma) {
            exprs.append(try parseAssignmentExpression())
        }
        return .sequence(ast.SequenceExpr(expressions: exprs, pos: pos))
    }

    func parseAssignmentExpression() throws -> ast.Expr {
        let left = try parseConditionalExpression()
        if current.IsAssignment {
            let op = current.Kind
            let pos = current.Pos
            advance()
            let right = try parseAssignmentExpression()
            return .assign(ast.AssignExpr(op: op, left: left, right: right, pos: pos))
        }
        return left
    }

    func parseConditionalExpression() throws -> ast.Expr {
        let test = try parseBinaryExpression(minPrec: 1)
        if match(.question) {
            let pos = previous.Pos
            let cons = try parseAssignmentExpression()
            try expect(.colon)
            let alt = try parseAssignmentExpression()
            return .conditional(ast.ConditionalExpr(test: test, consequent: cons, alternate: alt, pos: pos))
        }
        return test
    }

    func parseBinaryExpression(minPrec: int) throws -> ast.Expr {
        var left = try parseUnaryExpression()
        while true {
            let prec = token.Precedence(current.Kind)
            if prec < minPrec {
                break
            }
            let op = current.Kind
            let pos = current.Pos
            advance()
            // Right-associative for **
            let nextMinPrec = (op == .exp) ? prec : prec + 1
            let right = try parseBinaryExpression(minPrec: nextMinPrec)
            if op == .logicalAnd || op == .logicalOr || op == .nullishCoalesce {
                left = .logical(ast.LogicalExpr(op: op, left: left, right: right, pos: pos))
            } else {
                left = .binary(ast.BinaryExpr(op: op, left: left, right: right, pos: pos))
            }
        }
        return left
    }

    func parseUnaryExpression() throws -> ast.Expr {
        switch current.Kind {
        case .logicalNot, .bitNot, .add, .sub, .kTypeof, .kVoid, .kDelete:
            let op = current.Kind
            let pos = current.Pos
            advance()
            let arg = try parseUnaryExpression()
            return .unary(ast.UnaryExpr(op: op, argument: arg, prefix: true, pos: pos))
        case .inc, .dec:
            let op = current.Kind
            let pos = current.Pos
            advance()
            let arg = try parseUnaryExpression()
            return .unary(ast.UnaryExpr(op: op, argument: arg, prefix: true, pos: pos))
        default:
            return try parsePostfixExpression()
        }
    }

    func parsePostfixExpression() throws -> ast.Expr {
        let left = try parseLeftHandSideExpression()
        if !current.HasPrecedingLineBreak && (check(.inc) || check(.dec)) {
            let op = current.Kind
            let pos = current.Pos
            advance()
            return .unary(ast.UnaryExpr(op: op, argument: left, prefix: false, pos: pos))
        }
        return left
    }

    func parseLeftHandSideExpression() throws -> ast.Expr {
        var expr = try parsePrimaryExpression()

        while true {
            if match(.dot) {
                let pos = previous.Pos
                let propName = try parseIdentifierName()
                let propExpr = ast.Expr.identifier(ast.IdentifierExpr(propName, pos: pos))
                expr = .member(ast.MemberExpr(object: expr, property: propExpr, computed: false, optional: false, pos: pos))
            } else if match(.questionDot) {
                let pos = previous.Pos
                if match(.lBracket) {
                    let prop = try parseExpression()
                    try expect(.rBracket)
                    expr = .member(ast.MemberExpr(object: expr, property: prop, computed: true, optional: true, pos: pos))
                } else if match(.lParen) {
                    let args = try parseArguments()
                    expr = .call(ast.CallExpr(callee: expr, arguments: args, optional: true, pos: pos))
                } else {
                    let propName = try parseIdentifierName()
                    let propExpr = ast.Expr.identifier(ast.IdentifierExpr(propName, pos: pos))
                    expr = .member(ast.MemberExpr(object: expr, property: propExpr, computed: false, optional: true, pos: pos))
                }
            } else if match(.lBracket) {
                let pos = previous.Pos
                let prop = try parseExpression()
                try expect(.rBracket)
                expr = .member(ast.MemberExpr(object: expr, property: prop, computed: true, optional: false, pos: pos))
            } else if match(.lParen) {
                let pos = previous.Pos
                let args = try parseArguments()
                expr = .call(ast.CallExpr(callee: expr, arguments: args, optional: false, pos: pos))
            } else {
                break
            }
        }
        return expr
    }

    func parseArguments() throws -> [ast.Expr] {
        var args: [ast.Expr] = []
        if !check(.rParen) {
            while true {
                args.append(try parseAssignmentExpression())
                if !match(.comma) { break }
            }
        }
        try expect(.rParen)
        return args
    }

    func parsePrimaryExpression() throws -> ast.Expr {
        let pos = current.Pos
        switch current.Kind {
        case .identifier, .kOf, .kAs, .kFrom, .kGet, .kSet, .kTarget, .kStatic:
            let name = current.Text
            advance()
            if match(.arrow) {
                // Arrow function: x => ...
                if check(.lBrace) {
                    guard case .block(let b) = try parseBlockStatement() else {
                        throw error("expected block")
                    }
                    return .arrow(ast.ArrowExpr(params: [name], bodyStmt: b, pos: pos))
                }
                let bodyExpr = try parseAssignmentExpression()
                return .arrow(ast.ArrowExpr(params: [name], bodyExpr: bodyExpr, pos: pos))
            }
            return .identifier(ast.IdentifierExpr(name, pos: pos))

        case .number:
            let raw = current.Text
            let val = parseNumber(raw)
            advance()
            return .number(ast.NumberLiteralExpr(val, raw: raw, pos: pos))

        case .string:
            let raw = current.Text
            let val = parseString(raw)
            advance()
            return .string(ast.StringLiteralExpr(val, raw: raw, pos: pos))

        case .kTrue:
            advance()
            return .boolean(ast.BooleanLiteralExpr(true, pos: pos))

        case .kFalse:
            advance()
            return .boolean(ast.BooleanLiteralExpr(false, pos: pos))

        case .kNull:
            advance()
            return .nullLit(pos)

        case .kThis:
            advance()
            return .thisExpr(pos)

        case .lBracket:
            return try parseArrayLiteral()

        case .lBrace:
            return try parseObjectLiteral()

        case .lParen:
            advance()
            if match(.rParen) {
                // () => ...
                try expect(.arrow)
                if check(.lBrace) {
                    guard case .block(let b) = try parseBlockStatement() else {
                        throw error("expected block")
                    }
                    return .arrow(ast.ArrowExpr(params: [], bodyStmt: b, pos: pos))
                }
                let bodyExpr = try parseAssignmentExpression()
                return .arrow(ast.ArrowExpr(params: [], bodyExpr: bodyExpr, pos: pos))
            }
            let expr = try parseExpression()
            try expect(.rParen)
            if match(.arrow) {
                // (a, b) => ...
                var params: [string] = []
                if case .identifier(let id) = expr {
                    params.append(id.Name)
                } else if case .sequence(let seq) = expr {
                    for item in seq.Expressions {
                        if case .identifier(let id) = item {
                            params.append(id.Name)
                        } else {
                            throw error("invalid arrow function parameter")
                        }
                    }
                }
                if check(.lBrace) {
                    guard case .block(let b) = try parseBlockStatement() else {
                        throw error("expected block")
                    }
                    return .arrow(ast.ArrowExpr(params: params, bodyStmt: b, pos: pos))
                }
                let bodyExpr = try parseAssignmentExpression()
                return .arrow(ast.ArrowExpr(params: params, bodyExpr: bodyExpr, pos: pos))
            }
            return expr

        case .kFunction:
            return try parseFunctionExpression()

        case .kNew:
            advance()
            let callee = try parsePrimaryExpression()
            var args: [ast.Expr] = []
            if match(.lParen) {
                args = try parseArguments()
            }
            return .newExpr(ast.NewExpr(callee: callee, arguments: args, pos: pos))

        case .templateNoSub:
            let raw = current.Text
            let content = raw.count >= 2 ? String(raw.dropFirst().dropLast()) : ""
            advance()
            return .template(ast.TemplateExpr(quasis: [content], expressions: [], pos: pos))

        default:
            throw error("unexpected token \(current.Kind) ('\(current.Text)')")
        }
    }

    func parseArrayLiteral() throws -> ast.Expr {
        let pos = current.Pos
        try expect(.lBracket)
        var elements: [ast.Expr?] = []
        while !check(.rBracket) && !check(.eof) {
            if match(.comma) {
                elements.append(nil) // elision (hole)
            } else {
                elements.append(try parseAssignmentExpression())
                if !match(.comma) { break }
            }
        }
        try expect(.rBracket)
        return .array(ast.ArrayExpr(elements: elements, pos: pos))
    }

    func parseObjectLiteral() throws -> ast.Expr {
        let pos = current.Pos
        try expect(.lBrace)
        var props: [ast.ObjectProperty] = []
        while !check(.rBrace) && !check(.eof) {
            let propPos = current.Pos
            let keyExpr: ast.Expr
            var shorthand = false
            if current.IsIdentifierName {
                let name = current.Text
                advance()
                keyExpr = .identifier(ast.IdentifierExpr(name, pos: propPos))
                if match(.colon) {
                    let val = try parseAssignmentExpression()
                    props.append(ast.ObjectProperty(Key: keyExpr, Value: val, Kind: .propInit, Shorthand: false, Pos: propPos))
                } else {
                    // Shorthand: { x }
                    shorthand = true
                    props.append(ast.ObjectProperty(Key: keyExpr, Value: keyExpr, Kind: .propInit, Shorthand: true, Pos: propPos))
                }
            } else if check(.string) {
                let strVal = parseString(current.Text)
                advance()
                keyExpr = .string(ast.StringLiteralExpr(strVal, pos: propPos))
                try expect(.colon)
                let val = try parseAssignmentExpression()
                props.append(ast.ObjectProperty(Key: keyExpr, Value: val, Kind: .propInit, Shorthand: false, Pos: propPos))
            } else if match(.lBracket) {
                let compKey = try parseAssignmentExpression()
                try expect(.rBracket)
                try expect(.colon)
                let val = try parseAssignmentExpression()
                props.append(ast.ObjectProperty(Key: compKey, Value: val, Kind: .propInit, Computed: true, Shorthand: false, Pos: propPos))
            } else {
                throw error("invalid property in object literal")
            }

            if !match(.comma) { break }
        }
        try expect(.rBrace)
        return .object(ast.ObjectExpr(properties: props, pos: pos))
    }

    func parseFunctionExpression() throws -> ast.Expr {
        let pos = current.Pos
        try expect(.kFunction)
        var name: string? = nil
        if check(.identifier) {
            name = current.Text
            advance()
        }
        try expect(.lParen)
        var params: [string] = []
        if !check(.rParen) {
            while true {
                params.append(current.Text)
                try expect(.identifier)
                if !match(.comma) { break }
            }
        }
        try expect(.rParen)
        guard case .block(let body) = try parseBlockStatement() else {
            throw error("expected function block body")
        }
        return .function(ast.FunctionExpr(id: name, params: params, body: body, pos: pos))
    }

    func parseNumber(_ text: string) -> float64 {
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            let hexStr = String(text.dropFirst(2))
            var res: int64 = 0
            for b in [uint8](hexStr.utf8) {
                if b >= 0x30 && b <= 0x39 { res = res * 16 + int64(b - 0x30) }
                else if b >= 0x61 && b <= 0x66 { res = res * 16 + int64(b - 0x61 + 10) }
                else if b >= 0x41 && b <= 0x46 { res = res * 16 + int64(b - 0x41 + 10) }
            }
            return float64(res)
        }
        return float64(text) ?? 0.0
    }

    func parseString(_ text: string) -> string {
        if text.count < 2 { return text }
        // Trim enclosing quotes
        let bytes = [uint8](text.utf8)
        var result: [uint8] = []
        var i = 1
        let limit = bytes.count - 1
        while i < limit {
            let b = bytes[i]
            if b == 0x5C && i + 1 < limit { // \ escape
                i += 1
                let next = bytes[i]
                switch next {
                case 0x6E: result.append(0x0A) // \n
                case 0x72: result.append(0x0D) // \r
                case 0x74: result.append(0x09) // \t
                case 0x22: result.append(0x22) // \"
                case 0x27: result.append(0x27) // \'
                case 0x5C: result.append(0x5C) // \\
                case 0x30: result.append(0x00) // \0
                default: result.append(next)
                }
            } else {
                result.append(b)
            }
            i += 1
        }
        return String(decoding: result, as: UTF8.self)
    }
}
