package printer

import (
    "js/ast"
    "js/token"
)

/// Print renders an AST Program as JavaScript source text.
public func Print(_ program: ast.Program) -> string {
    var p = Printer()
    for s in program.Body {
        p.printStmt(s)
    }
    return p.output
}

/// PrintStmt renders an individual statement as source text.
public func PrintStmt(_ stmt: ast.Stmt) -> string {
    var p = Printer()
    p.printStmt(stmt)
    return p.output
}

/// PrintExpr renders an expression as source text.
public func PrintExpr(_ expr: ast.Expr) -> string {
    var p = Printer()
    p.printExpr(expr)
    return p.output
}

struct Printer {
    var output: string = ""
    var indentLevel: int = 0

    mutating func indent() {
        for _ in 0..<indentLevel {
            output += "  "
        }
    }

    mutating func printStmt(_ stmt: ast.Stmt) {
        switch stmt {
        case .empty:
            indent()
            output += ";\n"

        case .expr(let e):
            indent()
            printExpr(e.Expression)
            output += ";\n"

        case .block(let b):
            indent()
            output += "{\n"
            indentLevel += 1
            for s in b.Statements {
                printStmt(s)
            }
            indentLevel -= 1
            indent()
            output += "}\n"

        case .varDecl(let v):
            indent()
            output += "\(v.Kind) "
            for i in 0..<v.Declarations.count {
                if i > 0 { output += ", " }
                let d = v.Declarations[i]
                if let pat = d.Pattern {
                    printPattern(pat)
                } else {
                    output += d.Id
                }
                if let initExpr = d.Init {
                    output += " = "
                    printExpr(initExpr)
                }
            }
            output += ";\n"

        case .functionDecl(let f):
            indent()
            if f.IsAsync { output += "async " }
            output += "function "
            if f.IsGenerator { output += "* " }
            output += "\(f.Name)("
            var pList = f.Params
            if let rp = f.RestParam {
                pList.append("..." + rp)
            }
            output += pList.joined(separator: ", ")
            output += ") {\n"
            indentLevel += 1
            for s in f.Body.Statements {
                printStmt(s)
            }
            indentLevel -= 1
            indent()
            output += "}\n"

        case .ifStmt(let i):
            indent()
            output += "if ("
            printExpr(i.Test)
            output += ") "
            if case .block = i.Consequent {
                printStmt(i.Consequent)
            } else {
                output += "{\n"
                indentLevel += 1
                printStmt(i.Consequent)
                indentLevel -= 1
                indent()
                output += "}\n"
            }
            if let alt = i.Alternate {
                indent()
                output += "else "
                if case .ifStmt = alt {
                    printStmt(alt)
                } else if case .block = alt {
                    printStmt(alt)
                } else {
                    output += "{\n"
                    indentLevel += 1
                    printStmt(alt)
                    indentLevel -= 1
                    indent()
                    output += "}\n"
                }
            }

        case .whileStmt(let w):
            indent()
            output += "while ("
            printExpr(w.Test)
            output += ") {\n"
            indentLevel += 1
            printStmt(w.Body)
            indentLevel -= 1
            indent()
            output += "}\n"

        case .doWhileStmt(let d):
            indent()
            output += "do {\n"
            indentLevel += 1
            printStmt(d.Body)
            indentLevel -= 1
            indent()
            output += "} while ("
            printExpr(d.Test)
            output += ");\n"

        case .forStmt(let f):
            indent()
            output += "for ("
            if let is_ = f.InitStmt {
                // Strip newline and semicolon
                var temp = Printer()
                temp.printStmt(is_)
                var trimmed = temp.output
                if trimmed.hasSuffix(";\n") {
                    trimmed = String(trimmed.dropLast(2))
                }
                output += trimmed
            } else if let ie = f.InitExpr {
                printExpr(ie)
            }
            output += "; "
            if let t = f.Test { printExpr(t) }
            output += "; "
            if let u = f.Update { printExpr(u) }
            output += ") {\n"
            indentLevel += 1
            printStmt(f.Body)
            indentLevel -= 1
            indent()
            output += "}\n"

        case .forInStmt(let fi):
            indent()
            output += "for ("
            if let lv = fi.LeftVar {
                output += "\(lv.Kind) \(lv.Declarations[0].Id)"
            } else if let le = fi.LeftExpr {
                printExpr(le)
            }
            output += " in "
            printExpr(fi.Right)
            output += ") {\n"
            indentLevel += 1
            printStmt(fi.Body)
            indentLevel -= 1
            indent()
            output += "}\n"

        case .forOfStmt(let fo):
            indent()
            output += "for ("
            if let lv = fo.LeftVar {
                output += "\(lv.Kind) \(lv.Declarations[0].Id)"
            } else if let le = fo.LeftExpr {
                printExpr(le)
            }
            output += " of "
            printExpr(fo.Right)
            output += ") {\n"
            indentLevel += 1
            printStmt(fo.Body)
            indentLevel -= 1
            indent()
            output += "}\n"

        case .switchStmt(let sw):
            indent()
            output += "switch ("
            printExpr(sw.Discriminant)
            output += ") {\n"
            indentLevel += 1
            for c in sw.Cases {
                indent()
                if let t = c.Test {
                    output += "case "
                    printExpr(t)
                    output += ":\n"
                } else {
                    output += "default:\n"
                }
                indentLevel += 1
                for s in c.Consequent {
                    printStmt(s)
                }
                indentLevel -= 1
            }
            indentLevel -= 1
            indent()
            output += "}\n"

        case .returnStmt(let r):
            indent()
            output += "return"
            if let arg = r.Argument {
                output += " "
                printExpr(arg)
            }
            output += ";\n"

        case .breakStmt(let b):
            indent()
            output += "break"
            if let l = b.Label { output += " \(l)" }
            output += ";\n"

        case .continueStmt(let c):
            indent()
            output += "continue"
            if let l = c.Label { output += " \(l)" }
            output += ";\n"

        case .throwStmt(let t):
            indent()
            output += "throw "
            printExpr(t.Argument)
            output += ";\n"

        case .tryStmt(let tr):
            indent()
            output += "try {\n"
            indentLevel += 1
            for s in tr.Block.Statements {
                printStmt(s)
            }
            indentLevel -= 1
            indent()
            output += "}"
            if let h = tr.Handler {
                output += " catch"
                if let p = h.Param { output += " (\(p))" }
                output += " {\n"
                indentLevel += 1
                for s in h.Body.Statements {
                    printStmt(s)
                }
                indentLevel -= 1
                indent()
                output += "}"
            }
            if let f = tr.Finalizer {
                output += " finally {\n"
                indentLevel += 1
                for s in f.Statements {
                    printStmt(s)
                }
                indentLevel -= 1
                indent()
                output += "}"
            }
            output += "\n"

        case .classDecl(let c):
            indent()
            output += "class \(c.Name)"
            if let sc = c.SuperClass {
                output += " extends "
                printExpr(sc)
            }
            output += " {\n"
            indentLevel += 1
            for el in c.Elements {
                indent()
                if el.IsStatic { output += "static " }
                if el.Kind == .get { output += "get " }
                else if el.Kind == .set { output += "set " }
                if el.Computed {
                    output += "["
                    printExpr(el.Key)
                    output += "]"
                } else {
                    printExpr(el.Key)
                }
                output += "(\(el.Value.Params.joined(separator: ", "))) {\n"
                indentLevel += 1
                for s in el.Value.Body.Statements {
                    printStmt(s)
                }
                indentLevel -= 1
                indent()
                output += "}\n"
            }
            indentLevel -= 1
            indent()
            output += "}\n"
        }
    }

    mutating func printExpr(_ expr: ast.Expr) {
        switch expr {
        case .identifier(let id):
            output += id.Name

        case .number(let n):
            output += n.Raw.isEmpty ? "\(n.Value)" : n.Raw

        case .string(let s):
            output += "\"\(escapeString(s.Value))\""

        case .boolean(let b):
            output += b.Value ? "true" : "false"

        case .nullLit:
            output += "null"

        case .undefinedLit:
            output += "undefined"

        case .thisExpr:
            output += "this"

        case .binary(let b):
            output += "("
            printExpr(b.Left)
            output += " \(opString(b.Op)) "
            printExpr(b.Right)
            output += ")"

        case .unary(let u):
            if u.Prefix {
                output += opString(u.Op)
                if u.Op == .kTypeof || u.Op == .kVoid || u.Op == .kDelete {
                    output += " "
                }
                printExpr(u.Argument)
            } else {
                printExpr(u.Argument)
                output += opString(u.Op)
            }

        case .assign(let a):
            printExpr(a.Left)
            output += " \(opString(a.Op)) "
            printExpr(a.Right)

        case .logical(let l):
            output += "("
            printExpr(l.Left)
            output += " \(opString(l.Op)) "
            printExpr(l.Right)
            output += ")"

        case .conditional(let c):
            output += "("
            printExpr(c.Test)
            output += " ? "
            printExpr(c.Consequent)
            output += " : "
            printExpr(c.Alternate)
            output += ")"

        case .member(let m):
            printExpr(m.Object)
            if m.Optional { output += "?." }
            if m.Computed {
                if !m.Optional { output += "[" } else { output += "[" }
                printExpr(m.Property)
                output += "]"
            } else {
                if !m.Optional { output += "." }
                printExpr(m.Property)
            }

        case .call(let c):
            printExpr(c.Callee)
            if c.Optional { output += "?." }
            output += "("
            for i in 0..<c.Arguments.count {
                if i > 0 { output += ", " }
                printExpr(c.Arguments[i])
            }
            output += ")"

        case .newExpr(let n):
            output += "new "
            printExpr(n.Callee)
            output += "("
            for i in 0..<n.Arguments.count {
                if i > 0 { output += ", " }
                printExpr(n.Arguments[i])
            }
            output += ")"

        case .array(let a):
            output += "["
            for i in 0..<a.Elements.count {
                if i > 0 { output += ", " }
                if let el = a.Elements[i] {
                    printExpr(el)
                }
            }
            output += "]"

        case .object(let o):
            output += "{"
            for i in 0..<o.Properties.count {
                if i > 0 { output += ", " }
                let p = o.Properties[i]
                if p.IsSpread {
                    output += "..."
                    printExpr(p.Value)
                } else if p.Shorthand {
                    printExpr(p.Key)
                } else if p.Computed {
                    output += "["
                    printExpr(p.Key)
                    output += "]: "
                    printExpr(p.Value)
                } else {
                    printExpr(p.Key)
                    output += ": "
                    printExpr(p.Value)
                }
            }
            output += "}"

        case .function(let f):
            if f.IsAsync { output += "async " }
            output += "function"
            if let n = f.Id { output += " \(n)" }
            output += "("
            var pList = f.Params
            if let rp = f.RestParam {
                pList.append("..." + rp)
            }
            output += pList.joined(separator: ", ")
            output += ") {\n"
            indentLevel += 1
            for s in f.Body.Statements {
                printStmt(s)
            }
            indentLevel -= 1
            indent()
            output += "}"

        case .arrow(let a):
            if a.IsAsync { output += "async " }
            var pList = a.Params
            if let rp = a.RestParam {
                pList.append("..." + rp)
            }
            if pList.count == 1 && a.RestParam == nil {
                output += pList[0]
            } else {
                output += "(\(pList.joined(separator: ", ")))"
            }
            output += " => "
            if let bStmt = a.BodyStmt {
                output += "{\n"
                indentLevel += 1
                for s in bStmt.Statements {
                    printStmt(s)
                }
                indentLevel -= 1
                indent()
                output += "}"
            } else if let bExpr = a.BodyExpr {
                printExpr(bExpr)
            }

        case .sequence(let s):
            output += "("
            for i in 0..<s.Expressions.count {
                if i > 0 { output += ", " }
                printExpr(s.Expressions[i])
            }
            output += ")"

        case .template(let t):
            output += "`"
            for i in 0..<t.Quasis.count {
                output += t.Quasis[i]
                if i < t.Expressions.count {
                    output += "${"
                    printExpr(t.Expressions[i])
                    output += "}"
                }
            }
            output += "`"

        case .spread(let s):
            output += "..."
            printExpr(s.Argument)

        case .classExpr(let c):
            output += "class"
            if let n = c.Name { output += " \(n)" }
            if let sc = c.SuperClass {
                output += " extends "
                printExpr(sc)
            }
            output += " {\n"
            indentLevel += 1
            for el in c.Elements {
                indent()
                if el.IsStatic { output += "static " }
                if el.Kind == .get { output += "get " }
                else if el.Kind == .set { output += "set " }
                if el.Computed {
                    output += "["
                    printExpr(el.Key)
                    output += "]"
                } else {
                    printExpr(el.Key)
                }
                var pList = el.Value.Params
                if let rp = el.Value.RestParam {
                    pList.append("..." + rp)
                }
                output += "(\(pList.joined(separator: ", "))) {\n"
                indentLevel += 1
                for s in el.Value.Body.Statements {
                    printStmt(s)
                }
                indentLevel -= 1
                indent()
                output += "}\n"
            }
            indentLevel -= 1
            indent()
            output += "}"

        case .superExpr:
            output += "super"

        case .pattern(let p):
            printPattern(p)

        case .awaitExpr(let a):
            output += "await "
            printExpr(a.Argument)

        case .yieldExpr(let y):
            output += "yield"
            if y.Delegate { output += "*" }
            if let arg = y.Argument {
                output += " "
                printExpr(arg)
            }
        }
    }

    mutating func printDestructureTarget(_ target: ast.DestructureTarget) {
        switch target {
        case .identifier(let name):
            output += name
        case .member(let m):
            printExpr(.member(m))
        case .pattern(let p):
            printPattern(p)
        }
    }

    mutating func printPattern(_ p: ast.BindingPattern) {
        switch p {
        case .array(let arr):
            output += "["
            for i in 0..<arr.Elements.count {
                if i > 0 { output += ", " }
                let el = arr.Elements[i]
                if el.IsSpread { output += "..." }
                if let t = el.Target {
                    printDestructureTarget(t)
                }
                if let def = el.DefaultValue {
                    output += " = "
                    printExpr(def)
                }
            }
            output += "]"
        case .object(let obj):
            output += "{"
            for i in 0..<obj.Properties.count {
                if i > 0 { output += ", " }
                let prop = obj.Properties[i]
                if prop.IsSpread {
                    output += "..."
                    printDestructureTarget(prop.Target)
                } else {
                    if let comp = prop.ComputedKey {
                        output += "["
                        printExpr(comp)
                        output += "]: "
                        printDestructureTarget(prop.Target)
                    } else if case .identifier(let name) = prop.Target, name == prop.Key {
                        output += prop.Key
                    } else {
                        output += prop.Key + ": "
                        printDestructureTarget(prop.Target)
                    }
                    if let def = prop.DefaultValue {
                        output += " = "
                        printExpr(def)
                    }
                }
            }
            output += "}"
        }
    }

    func opString(_ kind: token.TokenKind) -> string {
        switch kind {
        case .add: return "+"
        case .sub: return "-"
        case .mul: return "*"
        case .div: return "/"
        case .mod: return "%"
        case .exp: return "**"
        case .assign: return "="
        case .addAssign: return "+="
        case .subAssign: return "-="
        case .mulAssign: return "*="
        case .divAssign: return "/="
        case .modAssign: return "%="
        case .expAssign: return "**="
        case .eq: return "=="
        case .notEq: return "!="
        case .strictEq: return "==="
        case .strictNotEq: return "!=="
        case .less: return "<"
        case .lessEq: return "<="
        case .greater: return ">"
        case .greaterEq: return ">="
        case .logicalAnd: return "&&"
        case .logicalOr: return "||"
        case .nullishCoalesce: return "??"
        case .logicalNot: return "!"
        case .bitAnd: return "&"
        case .bitOr: return "|"
        case .bitXor: return "^"
        case .bitNot: return "~"
        case .shl: return "<<"
        case .shr: return ">>"
        case .ushr: return ">>>"
        case .inc: return "++"
        case .dec: return "--"
        case .kTypeof: return "typeof"
        case .kVoid: return "void"
        case .kDelete: return "delete"
        case .kIn: return "in"
        case .kInstanceof: return "instanceof"
        default: return ""
        }
    }

    func escapeString(_ s: string) -> string {
        var res = ""
        for b in [uint8](s.utf8) {
            switch b {
            case 0x0A: res += "\\n"
            case 0x0D: res += "\\r"
            case 0x09: res += "\\t"
            case 0x22: res += "\\\""
            case 0x5C: res += "\\\\"
            default: res += String(decoding: [b], as: UTF8.self)
            }
        }
        return res
    }
}
