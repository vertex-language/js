package ast

import "js/token"

/// PropertyKind distinguishes object property definitions.
public enum PropertyKind: Equatable {
    case propInit
    case propGet
    case propSet
}

/// Property represents a key-value or method in an object literal.
public final class ObjectProperty {
    public var Key: Expr
    public var Value: Expr
    public var Kind: PropertyKind
    public var Computed: bool
    public var Shorthand: bool
    public var Pos: int

    public init(Key: Expr, Value: Expr, Kind: PropertyKind = .propInit, Computed: bool = false, Shorthand: bool = false, Pos: int = 0) {
        self.Key = Key
        self.Value = Value
        self.Kind = Kind
        self.Computed = Computed
        self.Shorthand = Shorthand
        self.Pos = Pos
    }
}

/// VariableDeclarator binds a pattern/name to an initial value.
public final class VariableDeclarator {
    public var Id: string
    public var Init: Expr?
    public var Pos: int

    public init(Id: string, Init: Expr? = nil, Pos: int = 0) {
        self.Id = Id
        self.Init = Init
        self.Pos = Pos
    }
}

/// SwitchCase represents one case or default clause in a switch statement.
public final class SwitchCase {
    public var Test: Expr? // nil for default
    public var Consequent: [Stmt]
    public var Pos: int

    public init(Test: Expr? = nil, Consequent: [Stmt] = [], Pos: int = 0) {
        self.Test = Test
        self.Consequent = Consequent
        self.Pos = Pos
    }
}

/// CatchClause represents a catch block with an optional binding variable.
public final class CatchClause {
    public var Param: string?
    public var Body: BlockStmt
    public var Pos: int

    public init(Param: string? = nil, Body: BlockStmt, Pos: int = 0) {
        self.Param = Param
        self.Body = Body
        self.Pos = Pos
    }
}

// MARK: - Expression Nodes

public final class IdentifierExpr {
    public var Name: string
    public var Pos: int
    public init(_ name: string, pos: int = 0) {
        self.Name = name
        self.Pos = pos
    }
}

public final class NumberLiteralExpr {
    public var Value: float64
    public var Raw: string
    public var Pos: int
    public init(_ value: float64, raw: string = "", pos: int = 0) {
        self.Value = value
        self.Raw = raw
        self.Pos = pos
    }
}

public final class StringLiteralExpr {
    public var Value: string
    public var Raw: string
    public var Pos: int
    public init(_ value: string, raw: string = "", pos: int = 0) {
        self.Value = value
        self.Raw = raw
        self.Pos = pos
    }
}

public final class BooleanLiteralExpr {
    public var Value: bool
    public var Pos: int
    public init(_ value: bool, pos: int = 0) {
        self.Value = value
        self.Pos = pos
    }
}

public final class BinaryExpr {
    public var Op: token.TokenKind
    public var Left: Expr
    public var Right: Expr
    public var Pos: int
    public init(op: token.TokenKind, left: Expr, right: Expr, pos: int = 0) {
        self.Op = op
        self.Left = left
        self.Right = right
        self.Pos = pos
    }
}

public final class UnaryExpr {
    public var Op: token.TokenKind
    public var Argument: Expr
    public var Prefix: bool
    public var Pos: int
    public init(op: token.TokenKind, argument: Expr, prefix: bool = true, pos: int = 0) {
        self.Op = op
        self.Argument = argument
        self.Prefix = prefix
        self.Pos = pos
    }
}

public final class AssignExpr {
    public var Op: token.TokenKind
    public var Left: Expr
    public var Right: Expr
    public var Pos: int
    public init(op: token.TokenKind, left: Expr, right: Expr, pos: int = 0) {
        self.Op = op
        self.Left = left
        self.Right = right
        self.Pos = pos
    }
}

public final class LogicalExpr {
    public var Op: token.TokenKind
    public var Left: Expr
    public var Right: Expr
    public var Pos: int
    public init(op: token.TokenKind, left: Expr, right: Expr, pos: int = 0) {
        self.Op = op
        self.Left = left
        self.Right = right
        self.Pos = pos
    }
}

public final class ConditionalExpr {
    public var Test: Expr
    public var Consequent: Expr
    public var Alternate: Expr
    public var Pos: int
    public init(test: Expr, consequent: Expr, alternate: Expr, pos: int = 0) {
        self.Test = test
        self.Consequent = consequent
        self.Alternate = alternate
        self.Pos = pos
    }
}

public final class MemberExpr {
    public var Object: Expr
    public var Property: Expr
    public var Computed: bool
    public var Optional: bool
    public var Pos: int
    public init(object: Expr, property: Expr, computed: bool = false, optional: bool = false, pos: int = 0) {
        self.Object = object
        self.Property = property
        self.Computed = computed
        self.Optional = optional
        self.Pos = pos
    }
}

public final class CallExpr {
    public var Callee: Expr
    public var Arguments: [Expr]
    public var Optional: bool
    public var Pos: int
    public init(callee: Expr, arguments: [Expr] = [], optional: bool = false, pos: int = 0) {
        self.Callee = callee
        self.Arguments = arguments
        self.Optional = optional
        self.Pos = pos
    }
}

public final class NewExpr {
    public var Callee: Expr
    public var Arguments: [Expr]
    public var Pos: int
    public init(callee: Expr, arguments: [Expr] = [], pos: int = 0) {
        self.Callee = callee
        self.Arguments = arguments
        self.Pos = pos
    }
}

public final class ArrayExpr {
    public var Elements: [Expr?]
    public var Pos: int
    public init(elements: [Expr?] = [], pos: int = 0) {
        self.Elements = elements
        self.Pos = pos
    }
}

public final class ObjectExpr {
    public var Properties: [ObjectProperty]
    public var Pos: int
    public init(properties: [ObjectProperty] = [], pos: int = 0) {
        self.Properties = properties
        self.Pos = pos
    }
}

public final class FunctionExpr {
    public var Id: string?
    public var Params: [string]
    public var Body: BlockStmt
    public var IsAsync: bool
    public var IsGenerator: bool
    public var Pos: int
    public init(id: string? = nil, params: [string] = [], body: BlockStmt, isAsync: bool = false, isGenerator: bool = false, pos: int = 0) {
        self.Id = id
        self.Params = params
        self.Body = body
        self.IsAsync = isAsync
        self.IsGenerator = isGenerator
        self.Pos = pos
    }
}

public final class ArrowExpr {
    public var Params: [string]
    public var BodyStmt: BlockStmt?
    public var BodyExpr: Expr?
    public var IsAsync: bool
    public var Pos: int
    public init(params: [string] = [], bodyStmt: BlockStmt? = nil, bodyExpr: Expr? = nil, isAsync: bool = false, pos: int = 0) {
        self.Params = params
        self.BodyStmt = bodyStmt
        self.BodyExpr = bodyExpr
        self.IsAsync = isAsync
        self.Pos = pos
    }
}

public final class SequenceExpr {
    public var Expressions: [Expr]
    public var Pos: int
    public init(expressions: [Expr] = [], pos: int = 0) {
        self.Expressions = expressions
        self.Pos = pos
    }
}

public final class TemplateExpr {
    public var Quasis: [string]
    public var Expressions: [Expr]
    public var Pos: int
    public init(quasis: [string] = [], expressions: [Expr] = [], pos: int = 0) {
        self.Quasis = quasis
        self.Expressions = expressions
        self.Pos = pos
    }
}

/// Expr wraps all expression variations.
public enum Expr {
    case identifier(IdentifierExpr)
    case number(NumberLiteralExpr)
    case string(StringLiteralExpr)
    case boolean(BooleanLiteralExpr)
    case nullLit(int)
    case undefinedLit(int)
    case thisExpr(int)
    case binary(BinaryExpr)
    case unary(UnaryExpr)
    case assign(AssignExpr)
    case logical(LogicalExpr)
    case conditional(ConditionalExpr)
    case member(MemberExpr)
    case call(CallExpr)
    case newExpr(NewExpr)
    case array(ArrayExpr)
    case object(ObjectExpr)
    case function(FunctionExpr)
    case arrow(ArrowExpr)
    case sequence(SequenceExpr)
    case template(TemplateExpr)
}

// MARK: - Statement Nodes

public final class ExprStmt {
    public var Expression: Expr
    public var Pos: int
    public init(_ expression: Expr, pos: int = 0) {
        self.Expression = expression
        self.Pos = pos
    }
}

public final class BlockStmt {
    public var Statements: [Stmt]
    public var Pos: int
    public init(statements: [Stmt] = [], pos: int = 0) {
        self.Statements = statements
        self.Pos = pos
    }
}

public final class IfStmt {
    public var Test: Expr
    public var Consequent: Stmt
    public var Alternate: Stmt?
    public var Pos: int
    public init(test: Expr, consequent: Stmt, alternate: Stmt? = nil, pos: int = 0) {
        self.Test = test
        self.Consequent = consequent
        self.Alternate = alternate
        self.Pos = pos
    }
}

public final class WhileStmt {
    public var Test: Expr
    public var Body: Stmt
    public var Pos: int
    public init(test: Expr, body: Stmt, pos: int = 0) {
        self.Test = test
        self.Body = body
        self.Pos = pos
    }
}

public final class DoWhileStmt {
    public var Body: Stmt
    public var Test: Expr
    public var Pos: int
    public init(body: Stmt, test: Expr, pos: int = 0) {
        self.Body = body
        self.Test = test
        self.Pos = pos
    }
}

public final class ForStmt {
    public var InitStmt: Stmt?
    public var InitExpr: Expr?
    public var Test: Expr?
    public var Update: Expr?
    public var Body: Stmt
    public var Pos: int
    public init(initStmt: Stmt? = nil, initExpr: Expr? = nil, test: Expr? = nil, update: Expr? = nil, body: Stmt, pos: int = 0) {
        self.InitStmt = initStmt
        self.InitExpr = initExpr
        self.Test = test
        self.Update = update
        self.Body = body
        self.Pos = pos
    }
}

public final class ForInStmt {
    public var LeftVar: VarDecl?
    public var LeftExpr: Expr?
    public var Right: Expr
    public var Body: Stmt
    public var Pos: int
    public init(leftVar: VarDecl? = nil, leftExpr: Expr? = nil, right: Expr, body: Stmt, pos: int = 0) {
        self.LeftVar = leftVar
        self.LeftExpr = leftExpr
        self.Right = right
        self.Body = body
        self.Pos = pos
    }
}

public final class ForOfStmt {
    public var LeftVar: VarDecl?
    public var LeftExpr: Expr?
    public var Right: Expr
    public var Body: Stmt
    public var IsAwait: bool
    public var Pos: int
    public init(leftVar: VarDecl? = nil, leftExpr: Expr? = nil, right: Expr, body: Stmt, isAwait: bool = false, pos: int = 0) {
        self.LeftVar = leftVar
        self.LeftExpr = leftExpr
        self.Right = right
        self.Body = body
        self.IsAwait = isAwait
        self.Pos = pos
    }
}

public final class SwitchStmt {
    public var Discriminant: Expr
    public var Cases: [SwitchCase]
    public var Pos: int
    public init(discriminant: Expr, cases: [SwitchCase] = [], pos: int = 0) {
        self.Discriminant = discriminant
        self.Cases = cases
        self.Pos = pos
    }
}

public final class ReturnStmt {
    public var Argument: Expr?
    public var Pos: int
    public init(_ argument: Expr? = nil, pos: int = 0) {
        self.Argument = argument
        self.Pos = pos
    }
}

public final class BreakStmt {
    public var Label: string?
    public var Pos: int
    public init(label: string? = nil, pos: int = 0) {
        self.Label = label
        self.Pos = pos
    }
}

public final class ContinueStmt {
    public var Label: string?
    public var Pos: int
    public init(label: string? = nil, pos: int = 0) {
        self.Label = label
        self.Pos = pos
    }
}

public final class ThrowStmt {
    public var Argument: Expr
    public var Pos: int
    public init(_ argument: Expr, pos: int = 0) {
        self.Argument = argument
        self.Pos = pos
    }
}

public final class TryStmt {
    public var Block: BlockStmt
    public var Handler: CatchClause?
    public var Finalizer: BlockStmt?
    public var Pos: int
    public init(block: BlockStmt, handler: CatchClause? = nil, finalizer: BlockStmt? = nil, pos: int = 0) {
        self.Block = block
        self.Handler = handler
        self.Finalizer = finalizer
        self.Pos = pos
    }
}

public final class VarDecl {
    public var Kind: string // "var", "let", "const"
    public var Declarations: [VariableDeclarator]
    public var Pos: int
    public init(kind: string, declarations: [VariableDeclarator] = [], pos: int = 0) {
        self.Kind = kind
        self.Declarations = declarations
        self.Pos = pos
    }
}

public final class FunctionDecl {
    public var Name: string
    public var Params: [string]
    public var Body: BlockStmt
    public var IsAsync: bool
    public var IsGenerator: bool
    public var Pos: int
    public init(name: string, params: [string] = [], body: BlockStmt, isAsync: bool = false, isGenerator: bool = false, pos: int = 0) {
        self.Name = name
        self.Params = params
        self.Body = body
        self.IsAsync = isAsync
        self.IsGenerator = isGenerator
        self.Pos = pos
    }
}

public final class EmptyStmt {
    public var Pos: int
    public init(pos: int = 0) {
        self.Pos = pos
    }
}

/// Stmt wraps all statement variations.
public enum Stmt {
    case expr(ExprStmt)
    case block(BlockStmt)
    case ifStmt(IfStmt)
    case whileStmt(WhileStmt)
    case doWhileStmt(DoWhileStmt)
    case forStmt(ForStmt)
    case forInStmt(ForInStmt)
    case forOfStmt(ForOfStmt)
    case switchStmt(SwitchStmt)
    case returnStmt(ReturnStmt)
    case breakStmt(BreakStmt)
    case continueStmt(ContinueStmt)
    case throwStmt(ThrowStmt)
    case tryStmt(TryStmt)
    case varDecl(VarDecl)
    case functionDecl(FunctionDecl)
    case empty(EmptyStmt)
}

/// Program represents a parsed JavaScript script or module.
public final class Program {
    public var SourceType: string // "script" or "module"
    public var Body: [Stmt]
    public var Pos: int

    public init(sourceType: string = "script", body: [Stmt] = [], pos: int = 0) {
        self.SourceType = sourceType
        self.Body = body
        self.Pos = pos
    }
}
