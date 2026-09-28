// Package ast is the syntax tree the parser builds (ECMA-262 §13–§16).
//
// Expressions, statements and binding patterns are enums whose payloads
// are classes, so a node can be annotated in place: the scope analysis
// (js/scope) records each function's and block's Scope, and each
// identifier's resolved Binding, on the nodes themselves.
package ast

import "js/token"

// MARK: scopes (filled in by js/scope)

/// BindingKind is how a name was declared.
public enum BindingKind: Equatable {
    case varBinding       // var, and a sloppy function's own name
    case letBinding
    case constBinding
    case classBinding     // the inner, immutable name of a class
    case functionBinding  // a function declaration
    case parameter
    case catchParameter
    case calleeName       // a named function expression's own name
    case internalBinding  // this, new.target, arguments and other compiler temporaries
}

/// Binding is one declared name in one scope.
public final class Binding {
    public let Name: string
    public var Kind: BindingKind
    /// Captured is set when a nested function refers to the binding, so it
    /// must live in a heap context rather than a register.
    public var Captured: bool = false
    /// Slot is the register (not captured) or context slot (captured).
    public var Slot: int = -1
    public weak var Scope: Scope?
    /// NeedsTDZ is set for let, const and class bindings read before the
    /// analysis can prove they are initialized.
    public var NeedsTDZ: bool = false

    public init(name: string, kind: BindingKind) {
        self.Name = name
        self.Kind = kind
    }

    public var IsLexical: bool {
        return Kind == .letBinding || Kind == .constBinding || Kind == .classBinding
    }

    public var IsConst: bool {
        return Kind == .constBinding || Kind == .classBinding
    }
}

/// ScopeKind is what introduced a scope.
public enum ScopeKind: Equatable {
    case script      // a script's top level: vars go on the global object
    case module
    case function
    case block
    case catchClause
    case classBody
    case with        // the object environment of a with statement
    case eval        // a direct or indirect eval's top level
}

/// Scope is a static scope. The compiler lays out its bindings.
public final class Scope {
    public let Kind: ScopeKind
    public weak var Parent: Scope?
    public var Children: [Scope] = []
    public var Bindings: [string: Binding] = [:]
    /// Order is the declaration order of Bindings.
    public var Order: [Binding] = []
    /// Function is the scope of the enclosing function (or script).
    public weak var Function: Scope?
    /// NeedsContext is set when some binding here is captured, or the scope
    /// can be reached by name at runtime (eval, with).
    public var NeedsContext: bool = false
    /// ContextSlots counts the captured bindings.
    public var ContextSlots: int = 0
    /// Dynamic is set when names in this scope or below can't be resolved
    /// statically: a sloppy direct eval or a with statement is inside it.
    public var Dynamic: bool = false
    /// HasDirectEval is set when this scope itself calls eval directly.
    public var HasDirectEval: bool = false
    public var Strict: bool = false

    public init(kind: ScopeKind, parent: Scope?) {
        self.Kind = kind
        self.Parent = parent
        if let p = parent { p.Children.append(self) }
    }

    public var IsFunctionBoundary: bool {
        return Kind == .function || Kind == .script || Kind == .module || Kind == .eval
    }

    public func Lookup(_ name: string) -> Binding? {
        return Bindings[name]
    }

    public func Declare(_ name: string, _ kind: BindingKind) -> Binding {
        if let b = Bindings[name] { return b }
        let b = Binding(name: name, kind: kind)
        b.Scope = self
        Bindings[name] = b
        Order.append(b)
        return b
    }
}

// MARK: programs

public final class Program {
    public var Body: [Stmt]
    public var IsModule: bool
    public var Strict: bool
    public var Source: string
    public var Filename: string
    public var Scope: Scope? = nil
    /// VarNames and LexNames are the top-level declarations, for
    /// GlobalDeclarationInstantiation.
    public var VarNames: [string] = []
    public var FunctionDecls: [FunctionNode] = []
    public var LexNames: [string] = []
    public var ConstNames: [string] = []

    public init(body: [Stmt], isModule: bool, strict: bool, source: string, filename: string) {
        self.Body = body
        self.IsModule = isModule
        self.Strict = strict
        self.Source = source
        self.Filename = filename
    }
}

// MARK: expressions

public enum Expr {
    case number(NumberLit)
    case bigint(BigIntLit)
    case string(StringLit)
    case template(TemplateLit)
    case taggedTemplate(TaggedTemplate)
    case regex(RegExpLit)
    case boolean(BoolLit)
    case nullLit(Pos)
    case identifier(Identifier)
    case thisExpr(ThisExpr)
    case superMember(SuperMember)      // super.x, super[x]
    case superCall(SuperCall)          // super(...)
    case array(ArrayLit)
    case object(ObjectLit)
    case function(FunctionNode)        // function expressions and arrows
    case classExpr(ClassNode)
    case unary(UnaryExpr)
    case update(UpdateExpr)
    case binary(BinaryExpr)
    case logical(LogicalExpr)
    case assign(AssignExpr)
    case conditional(ConditionalExpr)
    case call(CallExpr)
    case newExpr(NewExpr)
    case member(MemberExpr)
    case optionalChain(OptionalChain)  // the boundary a ?. short-circuits to
    case sequence(SequenceExpr)
    case spread(SpreadElement)         // only inside arguments and arrays
    case yieldExpr(YieldExpr)
    case awaitExpr(AwaitExpr)
    case newTarget(NewTargetExpr)
    case importMeta(Pos)
    case importCall(ImportCall)
    case privateIn(PrivateInExpr)      // #x in obj
    case paren(ParenExpr)              // kept so (a) = 1 and ({a}) differ; the compiler unwraps it
    case hole(Pos)                     // an array elision: [a, , b]
}

/// Pos is a bare source position, for the payloads that need nothing else.
public final class Pos {
    public let At: int
    public init(_ at: int) { self.At = at }
}

public final class NumberLit {
    public let Value: float64
    public let At: int
    public init(_ v: float64, at: int) { self.Value = v; self.At = at }
}

public final class BigIntLit {
    /// Digits is the literal as written without the n, with its 0x, 0o or 0b prefix.
    public let Digits: string
    public let At: int
    public init(_ d: string, at: int) { self.Digits = d; self.At = at }
}

public final class StringLit {
    public let Value: [uint16]
    public let At: int
    public init(_ v: [uint16], at: int) { self.Value = v; self.At = at }
}

public final class TemplateLit {
    /// Cooked is nil where an escape was invalid (tagged templates only).
    public var Cooked: [[uint16]?]
    public var Raw: [string]
    public var Exprs: [Expr]
    public let At: int
    public init(cooked: [[uint16]?], raw: [string], exprs: [Expr], at: int) {
        self.Cooked = cooked
        self.Raw = raw
        self.Exprs = exprs
        self.At = at
    }
}

public final class TaggedTemplate {
    public var Tag: Expr
    public var Quasi: TemplateLit
    /// Site is filled by the compiler: the index of this call site's cached
    /// template object.
    public var Site: int = -1
    public let At: int
    public init(tag: Expr, quasi: TemplateLit, at: int) { self.Tag = tag; self.Quasi = quasi; self.At = at }
}

public final class RegExpLit {
    public let Pattern: string
    public let Flags: string
    public let At: int
    public init(pattern: string, flags: string, at: int) { self.Pattern = pattern; self.Flags = flags; self.At = at }
}

public final class BoolLit {
    public let Value: bool
    public let At: int
    public init(_ v: bool, at: int) { self.Value = v; self.At = at }
}

public final class Identifier {
    public let Name: string
    public let At: int
    /// Binding is the resolved declaration, or nil for a global or dynamic name.
    public var Binding: Binding? = nil
    /// Dynamic is set when the name must be looked up at runtime (with, eval).
    public var Dynamic: bool = false
    /// Depth is how many contexts out the binding's context is, when captured.
    public var Depth: int = 0
    public init(_ name: string, at: int) { self.Name = name; self.At = at }
}

public final class ThisExpr {
    public let At: int
    /// Binding is the function's this binding, when an arrow captures it.
    public var Binding: Binding? = nil
    public var Depth: int = 0
    public init(at: int) { self.At = at }
}

public final class NewTargetExpr {
    public let At: int
    public var Binding: Binding? = nil
    public var Depth: int = 0
    public init(at: int) { self.At = at }
}

public final class SuperMember {
    public var Property: Expr
    public var Computed: bool
    public let At: int
    public init(property: Expr, computed: bool, at: int) { self.Property = property; self.Computed = computed; self.At = at }
}

public final class SuperCall {
    public var Args: [Expr]
    public let At: int
    public init(args: [Expr], at: int) { self.Args = args; self.At = at }
}

public final class ArrayLit {
    public var Elements: [Expr]
    public let At: int
    public init(elements: [Expr], at: int) { self.Elements = elements; self.At = at }
}

public enum PropertyKind: Equatable {
    case initProp     // key: value, and shorthand
    case method       // key() {}
    case getter
    case setter
    case spread       // ...value
    case protoSetter  // __proto__: value
}

/// PropertyKey is how a property or class element is named.
public enum PropertyKey {
    case named(string)          // an identifier name, or a string or number literal's canonical string
    case computed(Expr)
    case privateName(string)    // #name, without the #
}

public final class Property {
    public var Kind: PropertyKind
    public var Key: PropertyKey
    public var Value: Expr
    public var Shorthand: bool
    public let At: int
    public init(kind: PropertyKind, key: PropertyKey, value: Expr, shorthand: bool = false, at: int) {
        self.Kind = kind
        self.Key = key
        self.Value = value
        self.Shorthand = shorthand
        self.At = at
    }
}

public final class ObjectLit {
    public var Properties: [Property]
    public let At: int
    /// CoverInitializers records shorthand-with-default ({a = 1}), which is
    /// only valid if the literal becomes a pattern.
    public var CoverInitAt: int = -1
    public init(properties: [Property], at: int) { self.Properties = properties; self.At = at }
}

public enum FunctionKind: Equatable {
    case normal
    case arrow
    case method
    case getter
    case setter
    case classConstructor
    case derivedConstructor
    case classFieldInit     // the synthetic function that runs a class's field initializers
    case staticBlock
}

/// Param is one formal parameter.
public final class Param {
    public var Target: Pattern
    public var Default: Expr?
    public init(target: Pattern, def: Expr? = nil) { self.Target = target; self.Default = def }
}

public final class FunctionNode {
    public var Name: string
    public var Kind: FunctionKind
    public var Params: [Param]
    public var Rest: Pattern?
    public var Body: [Stmt]
    /// ExprBody is set for a concise arrow body.
    public var ExprBody: Expr?
    public var IsAsync: bool
    public var IsGenerator: bool
    public var Strict: bool
    /// SimpleParams is set when every parameter is a plain identifier with
    /// no default and there is no rest: such functions get a mapped
    /// arguments object in sloppy mode.
    public var SimpleParams: bool = true
    public var IsExpression: bool = false
    /// Start and End are the byte offsets of the source text, for toString.
    public var Start: int
    public var End: int = 0
    public var Line: int = 0
    /// Filled by js/scope.
    public var Scope: Scope? = nil
    /// BodyScope is the scope for the body's lexical declarations when the
    /// parameters have expressions (defaults), which get their own scope.
    public var BodyScope: Scope? = nil
    public var UsesArguments: bool = false
    public var UsesThis: bool = false
    public var HasDirectEval: bool = false
    /// Class is set on a class's constructor and methods, for field setup.
    public weak var Class: ClassNode?
    /// VarNames and FunctionDecls are hoisted declarations of the body.
    public var VarNames: [string] = []
    public var FunctionDecls: [FunctionNode] = []
    /// FunctionNameBinding is a named function expression's own name.
    public var SelfBinding: Binding? = nil
    public var ThisBinding: Binding? = nil
    public var NewTargetBinding: Binding? = nil
    public var ArgumentsBinding: Binding? = nil
    public var HomeObjectBinding: Binding? = nil

    public init(name: string, kind: FunctionKind, params: [Param], rest: Pattern?, body: [Stmt], isAsync: bool, isGenerator: bool, strict: bool, start: int) {
        self.Name = name
        self.Kind = kind
        self.Params = params
        self.Rest = rest
        self.Body = body
        self.ExprBody = nil
        self.IsAsync = isAsync
        self.IsGenerator = isGenerator
        self.Strict = strict
        self.Start = start
    }

    public var IsArrow: bool { return Kind == .arrow }
}

public enum ClassElementKind: Equatable {
    case method
    case getter
    case setter
    case field
    case staticBlock
}

public final class ClassElement {
    public var Kind: ClassElementKind
    public var Key: PropertyKey
    public var IsStatic: bool
    /// Value is the method's function, or the field's initializer wrapped
    /// in a function (nil for a field with none).
    public var Value: FunctionNode?
    public let At: int
    public init(kind: ClassElementKind, key: PropertyKey, isStatic: bool, value: FunctionNode?, at: int) {
        self.Kind = kind
        self.Key = key
        self.IsStatic = isStatic
        self.Value = value
        self.At = at
    }
}

public final class ClassNode {
    public var Name: string
    public var SuperClass: Expr?
    public var Constructor: FunctionNode?
    public var Elements: [ClassElement]
    public let At: int
    public var End: int = 0
    public var Start: int = 0
    /// Scope holds the class's own name binding and its private names.
    public var Scope: Scope? = nil
    public var NameBinding: Binding? = nil
    public init(name: string, superClass: Expr?, elements: [ClassElement], at: int) {
        self.Name = name
        self.SuperClass = superClass
        self.Elements = elements
        self.At = at
    }
}

public final class UnaryExpr {
    public var Op: token.TokenKind   // sub, add, logicalNot, bitNot, kTypeof, kVoid, kDelete
    public var Argument: Expr
    public let At: int
    public init(op: token.TokenKind, argument: Expr, at: int) { self.Op = op; self.Argument = argument; self.At = at }
}

public final class UpdateExpr {
    public var Op: token.TokenKind   // inc, dec
    public var Prefix: bool
    public var Argument: Expr
    public let At: int
    public init(op: token.TokenKind, prefix: bool, argument: Expr, at: int) { self.Op = op; self.Prefix = prefix; self.Argument = argument; self.At = at }
}

public final class BinaryExpr {
    public var Op: token.TokenKind
    public var Left: Expr
    public var Right: Expr
    public let At: int
    public init(op: token.TokenKind, left: Expr, right: Expr, at: int) { self.Op = op; self.Left = left; self.Right = right; self.At = at }
}

public final class LogicalExpr {
    public var Op: token.TokenKind   // logicalAnd, logicalOr, nullishCoalesce
    public var Left: Expr
    public var Right: Expr
    public let At: int
    public init(op: token.TokenKind, left: Expr, right: Expr, at: int) { self.Op = op; self.Left = left; self.Right = right; self.At = at }
}

public final class AssignExpr {
    public var Op: token.TokenKind   // assign or a compound operator
    public var Target: Pattern
    public var Value: Expr
    public let At: int
    public init(op: token.TokenKind, target: Pattern, value: Expr, at: int) { self.Op = op; self.Target = target; self.Value = value; self.At = at }
}

public final class ConditionalExpr {
    public var Test: Expr
    public var Consequent: Expr
    public var Alternate: Expr
    public let At: int
    public init(test: Expr, consequent: Expr, alternate: Expr, at: int) { self.Test = test; self.Consequent = consequent; self.Alternate = alternate; self.At = at }
}

public final class CallExpr {
    public var Callee: Expr
    public var Args: [Expr]
    public var Optional: bool        // f?.()
    /// DirectEval is set by the parser for eval(...) called by that name.
    public var DirectEval: bool = false
    public let At: int
    public init(callee: Expr, args: [Expr], optional: bool, at: int) { self.Callee = callee; self.Args = args; self.Optional = optional; self.At = at }
}

public final class NewExpr {
    public var Callee: Expr
    public var Args: [Expr]
    public let At: int
    public init(callee: Expr, args: [Expr], at: int) { self.Callee = callee; self.Args = args; self.At = at }
}

public final class MemberExpr {
    public var Object: Expr
    /// Property is an identifier name (Name) or, when Computed, an expression.
    public var Name: string
    public var Property: Expr?
    public var Computed: bool
    public var Private: bool         // obj.#x
    public var Optional: bool        // obj?.x
    public let At: int
    public init(object: Expr, name: string, property: Expr?, computed: bool, isPrivate: bool, optional: bool, at: int) {
        self.Object = object
        self.Name = name
        self.Property = property
        self.Computed = computed
        self.Private = isPrivate
        self.Optional = optional
        self.At = at
    }
}

public final class OptionalChain {
    public var Expression: Expr
    public let At: int
    public init(_ e: Expr, at: int) { self.Expression = e; self.At = at }
}

public final class SequenceExpr {
    public var Expressions: [Expr]
    public let At: int
    public init(_ exprs: [Expr], at: int) { self.Expressions = exprs; self.At = at }
}

public final class SpreadElement {
    public var Argument: Expr
    public let At: int
    public init(_ arg: Expr, at: int) { self.Argument = arg; self.At = at }
}

public final class YieldExpr {
    public var Argument: Expr?
    public var Delegate: bool
    public let At: int
    public init(argument: Expr?, delegate: bool, at: int) { self.Argument = argument; self.Delegate = delegate; self.At = at }
}

public final class AwaitExpr {
    public var Argument: Expr
    public let At: int
    public init(_ arg: Expr, at: int) { self.Argument = arg; self.At = at }
}

public final class ImportCall {
    public var Source: Expr
    public let At: int
    public init(_ src: Expr, at: int) { self.Source = src; self.At = at }
}

public final class PrivateInExpr {
    public var Name: string
    public var Right: Expr
    public let At: int
    public init(name: string, right: Expr, at: int) { self.Name = name; self.Right = right; self.At = at }
}

public final class ParenExpr {
    public var Expression: Expr
    public let At: int
    public init(_ e: Expr, at: int) { self.Expression = e; self.At = at }
}

// MARK: patterns

/// Pattern is a binding or assignment target.
public enum Pattern {
    case identifier(Identifier)
    case member(Expr)                // assignment targets only: a.b, a[b], super.x
    case array(ArrayPattern)
    case object(ObjectPattern)
}

public final class PatternElement {
    public var Target: Pattern
    public var Default: Expr?
    public init(target: Pattern, def: Expr? = nil) { self.Target = target; self.Default = def }
}

public final class ArrayPattern {
    /// Elements holds nil for an elision.
    public var Elements: [PatternElement?]
    public var Rest: Pattern?
    public let At: int
    public init(elements: [PatternElement?], rest: Pattern?, at: int) { self.Elements = elements; self.Rest = rest; self.At = at }
}

public final class PatternProperty {
    public var Key: PropertyKey
    public var Value: PatternElement
    public init(key: PropertyKey, value: PatternElement) { self.Key = key; self.Value = value }
}

public final class ObjectPattern {
    public var Properties: [PatternProperty]
    public var Rest: Pattern?
    public let At: int
    public init(properties: [PatternProperty], rest: Pattern?, at: int) { self.Properties = properties; self.Rest = rest; self.At = at }
}

// MARK: statements

public enum Stmt {
    case varDecl(VarDecl)
    case functionDecl(FunctionNode)
    case classDecl(ClassNode)
    case expr(ExprStmt)
    case block(BlockStmt)
    case empty(Pos)
    case ifStmt(IfStmt)
    case forStmt(ForStmt)
    case forIn(ForInStmt)
    case forOf(ForInStmt)
    case whileStmt(WhileStmt)
    case doWhile(WhileStmt)
    case returnStmt(ReturnStmt)
    case breakStmt(JumpStmt)
    case continueStmt(JumpStmt)
    case throwStmt(ThrowStmt)
    case tryStmt(TryStmt)
    case switchStmt(SwitchStmt)
    case labeled(LabeledStmt)
    case with(WithStmt)
    case debugger(Pos)
    case importDecl(ImportDecl)
    case exportDecl(ExportDecl)
}

public enum DeclKind: Equatable {
    case varKind
    case letKind
    case constKind
}

public final class Declarator {
    public var Target: Pattern
    public var Init: Expr?
    public init(target: Pattern, initExpr: Expr?) { self.Target = target; self.Init = initExpr }
}

public final class VarDecl {
    public var Kind: DeclKind
    public var Declarations: [Declarator]
    public let At: int
    public init(kind: DeclKind, declarations: [Declarator], at: int) { self.Kind = kind; self.Declarations = declarations; self.At = at }
}

public final class ExprStmt {
    public var Expression: Expr
    public let At: int
    /// Directive is set for a "use strict"-style prologue string.
    public var Directive: bool = false
    public init(_ e: Expr, at: int) { self.Expression = e; self.At = at }
}

public final class BlockStmt {
    public var Body: [Stmt]
    public let At: int
    public var Scope: Scope? = nil
    public init(_ body: [Stmt], at: int) { self.Body = body; self.At = at }
}

public final class IfStmt {
    public var Test: Expr
    public var Consequent: Stmt
    public var Alternate: Stmt?
    public let At: int
    public init(test: Expr, consequent: Stmt, alternate: Stmt?, at: int) { self.Test = test; self.Consequent = consequent; self.Alternate = alternate; self.At = at }
}

public final class ForStmt {
    /// Init is a declaration (VarDecl) or an expression statement.
    public var Init: Stmt?
    public var Test: Expr?
    public var Update: Expr?
    public var Body: Stmt
    public let At: int
    /// Scope holds a let or const Init's bindings, copied per iteration.
    public var Scope: Scope? = nil
    public var Labels: [string] = []
    public init(initStmt: Stmt?, test: Expr?, update: Expr?, body: Stmt, at: int) {
        self.Init = initStmt
        self.Test = test
        self.Update = update
        self.Body = body
        self.At = at
    }
}

/// ForInStmt serves for-in, for-of and for-await-of.
public final class ForInStmt {
    /// Decl is set when the left side declares (var/let/const x); Target
    /// otherwise, an assignment target.
    public var Decl: VarDecl?
    public var Target: Pattern?
    public var Right: Expr
    public var Body: Stmt
    public var IsAwait: bool
    public let At: int
    public var Scope: Scope? = nil
    public var Labels: [string] = []
    public init(decl: VarDecl?, target: Pattern?, right: Expr, body: Stmt, isAwait: bool, at: int) {
        self.Decl = decl
        self.Target = target
        self.Right = right
        self.Body = body
        self.IsAwait = isAwait
        self.At = at
    }
}

public final class WhileStmt {
    public var Test: Expr
    public var Body: Stmt
    public let At: int
    public var Labels: [string] = []
    public init(test: Expr, body: Stmt, at: int) { self.Test = test; self.Body = body; self.At = at }
}

public final class ReturnStmt {
    public var Argument: Expr?
    public let At: int
    public init(_ arg: Expr?, at: int) { self.Argument = arg; self.At = at }
}

public final class JumpStmt {
    public var Label: string?
    public let At: int
    public init(label: string?, at: int) { self.Label = label; self.At = at }
}

public final class ThrowStmt {
    public var Argument: Expr
    public let At: int
    public init(_ arg: Expr, at: int) { self.Argument = arg; self.At = at }
}

public final class TryStmt {
    public var Block: BlockStmt
    /// Param is nil for catch without a binding, or no catch at all.
    public var Param: Pattern?
    public var Handler: BlockStmt?
    public var Finalizer: BlockStmt?
    public let At: int
    public var CatchScope: Scope? = nil
    public init(block: BlockStmt, param: Pattern?, handler: BlockStmt?, finalizer: BlockStmt?, at: int) {
        self.Block = block
        self.Param = param
        self.Handler = handler
        self.Finalizer = finalizer
        self.At = at
    }
}

public final class SwitchCase {
    public var Test: Expr?
    public var Body: [Stmt]
    public init(test: Expr?, body: [Stmt]) { self.Test = test; self.Body = body }
}

public final class SwitchStmt {
    public var Discriminant: Expr
    public var Cases: [SwitchCase]
    public let At: int
    public var Scope: Scope? = nil
    public var Labels: [string] = []
    public init(discriminant: Expr, cases: [SwitchCase], at: int) { self.Discriminant = discriminant; self.Cases = cases; self.At = at }
}

public final class LabeledStmt {
    public var Label: string
    public var Body: Stmt
    public let At: int
    public init(label: string, body: Stmt, at: int) { self.Label = label; self.Body = body; self.At = at }
}

public final class WithStmt {
    public var Object: Expr
    public var Body: Stmt
    public let At: int
    public var Scope: Scope? = nil
    public init(object: Expr, body: Stmt, at: int) { self.Object = object; self.Body = body; self.At = at }
}

public final class ImportSpecifier {
    /// Imported is the exported name ("default", "*" for a namespace).
    public var Imported: string
    public var Local: string
    public init(imported: string, local: string) { self.Imported = imported; self.Local = local }
}

public final class ImportDecl {
    public var Source: string
    public var Specifiers: [ImportSpecifier]
    public let At: int
    public init(source: string, specifiers: [ImportSpecifier], at: int) { self.Source = source; self.Specifiers = specifiers; self.At = at }
}

public final class ExportSpecifier {
    public var Local: string
    public var Exported: string
    public init(local: string, exported: string) { self.Local = local; self.Exported = exported }
}

public final class ExportDecl {
    /// Declaration is export var/let/const/function/class.
    public var Declaration: Stmt?
    /// DefaultExpr is export default <expression>.
    public var DefaultExpr: Expr?
    public var Specifiers: [ExportSpecifier]
    /// Source is set for export ... from "m".
    public var Source: string?
    public var StarAs: string?
    public var IsStar: bool = false
    public let At: int
    public init(at: int) {
        self.Declaration = nil
        self.DefaultExpr = nil
        self.Specifiers = []
        self.Source = nil
        self.StarAs = nil
        self.At = at
    }
}

// MARK: helpers

/// ExprPos is an expression's source offset.
public func ExprPos(_ e: Expr) -> int {
    switch e {
    case .number(let n): return n.At
    case .bigint(let n): return n.At
    case .string(let n): return n.At
    case .template(let n): return n.At
    case .taggedTemplate(let n): return n.At
    case .regex(let n): return n.At
    case .boolean(let n): return n.At
    case .nullLit(let p): return p.At
    case .identifier(let n): return n.At
    case .thisExpr(let n): return n.At
    case .superMember(let n): return n.At
    case .superCall(let n): return n.At
    case .array(let n): return n.At
    case .object(let n): return n.At
    case .function(let n): return n.Start
    case .classExpr(let n): return n.At
    case .unary(let n): return n.At
    case .update(let n): return n.At
    case .binary(let n): return n.At
    case .logical(let n): return n.At
    case .assign(let n): return n.At
    case .conditional(let n): return n.At
    case .call(let n): return n.At
    case .newExpr(let n): return n.At
    case .member(let n): return n.At
    case .optionalChain(let n): return n.At
    case .sequence(let n): return n.At
    case .spread(let n): return n.At
    case .yieldExpr(let n): return n.At
    case .awaitExpr(let n): return n.At
    case .newTarget(let n): return n.At
    case .importMeta(let p): return p.At
    case .importCall(let n): return n.At
    case .privateIn(let n): return n.At
    case .paren(let n): return n.At
    case .hole(let p): return p.At
    }
}

/// StripParens removes the parentheses around an expression.
public func StripParens(_ e: Expr) -> Expr {
    var cur = e
    while case .paren(let p) = cur {
        cur = p.Expression
    }
    return cur
}

/// IsAnonymousFunctionDefinition is the spec's test for giving an
/// anonymous function or class the name of what it is assigned to.
public func IsAnonymousFunctionDefinition(_ e: Expr) -> bool {
    switch e {
    case .function(let f): return f.Name.isEmpty
    case .classExpr(let c): return c.Name.isEmpty
    default: return false
    }
}

/// PatternNames lists the names a binding pattern declares, in order.
public func PatternNames(_ p: Pattern, _ out: inout [string]) {
    switch p {
    case .identifier(let id):
        out.append(id.Name)
    case .member:
        break
    case .array(let a):
        for el in a.Elements {
            if let e = el { PatternNames(e.Target, &out) }
        }
        if let r = a.Rest { PatternNames(r, &out) }
    case .object(let o):
        for prop in o.Properties { PatternNames(prop.Value.Target, &out) }
        if let r = o.Rest { PatternNames(r, &out) }
    }
}
