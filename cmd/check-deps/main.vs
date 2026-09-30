// check-deps reads every package's imports and checks them against the
// engine's layering: what each package may import from js. It fails on
// an import outside its package's list, and on a package with no rule.
//
//     vsc run ./cmd/check-deps        (from the repository root)
//
// The layers, bottom up:
//
//   str, token, regexp/syntax      no js imports
//   value                          str, token
//   ast, scanner                   token
//   parser, scope, printer         the front end below them
//   regexp                         regexp/syntax
//   bytecode                       str, value
//   codegen                        the front end, bytecode
//   object                         the runtime's base: str, value, bytecode
//   interp                         object, and the front end and codegen (eval, new Function)
//   builtin/*                      object and below, regexp, other built-ins; never interp or the compiler
//   js                             the embedding API: anything
package main

import "fs"

let frontEnd = ["js/token", "js/scanner", "js/ast", "js/parser", "js/scope"]
let runtimeBase = ["js/str", "js/value", "js/token", "js/bytecode", "js/object"]

/// allowed is each package's permitted js imports; a trailing / allows a prefix.
let allowed: [string: [string]] = [
    "js/str": [],
    "js/token": [],
    "js/regexp/syntax": [],
    "js/value": ["js/str", "js/token"],
    "js/ast": ["js/token"],
    "js/scanner": ["js/token"],
    "js/parser": ["js/token", "js/scanner", "js/ast"],
    "js/scope": ["js/token", "js/ast"],
    "js/printer": ["js/token", "js/ast"],
    "js/regexp": ["js/regexp/syntax"],
    "js/bytecode": ["js/str", "js/value"],
    "js/codegen": frontEnd + ["js/bytecode", "js/str", "js/value"],
    "js/object": ["js/str", "js/value", "js/bytecode"],
    "js/interp": frontEnd + ["js/codegen", "js/bytecode", "js/str", "js/value", "js/object"],
    "js/builtin/": runtimeBase + ["js/regexp", "js/regexp/syntax", "js/builtin/"],
    "js": ["js/"],
]

func permits(_ list: [string], _ imp: string) -> bool {
    for a in list {
        if a == imp { return true }
        if a.hasSuffix("/") && imp.hasPrefix(a) { return true }
    }
    return false
}

func ruleFor(_ pkg: string) -> [string]? {
    if let r = allowed[pkg] { return r }
    if pkg.hasPrefix("js/builtin/") { return allowed["js/builtin/"] }
    return nil
}

/// quoted is the text between the first pair of double quotes in b.
func quoted(_ b: [uint8]) -> string? {
    var i = 0
    while i < b.count && b[i] != 0x22 { i += 1 }
    var j = i + 1
    while j < b.count && b[j] != 0x22 { j += 1 }
    if j >= b.count { return nil }
    return string(decoding: Array(b[(i + 1)..<j]), as: UTF8.self)
}

func startsWith(_ b: [uint8], _ p: string) -> bool {
    let q = [uint8](p.utf8)
    if b.count < q.count { return false }
    var i = 0
    while i < q.count {
        if b[i] != q[i] { return false }
        i += 1
    }
    return true
}

/// imports reads the import paths of a source file.
func imports(_ text: string) -> [string] {
    var out: [string] = []
    var inBlock = false
    var line: [uint8] = []
    var bytes = [uint8](text.utf8)
    bytes.append(0x0A)
    for c in bytes {
        if c != 0x0A {
            if !(line.isEmpty && (c == 0x20 || c == 0x09)) { line.append(c) }
            continue
        }
        if inBlock {
            if startsWith(line, ")") {
                inBlock = false
            } else if let q = quoted(line) {
                out.append(q)
            }
        } else if startsWith(line, "import (") {
            inBlock = true
        } else if startsWith(line, "import \""), let q = quoted(line) {
            out.append(q)
        }
        line = []
    }
    return out
}

func main() -> int32 {
    var packages: [string: [string]] = [:]
    func visit(_ dir: fs.Path, _ pkg: string) throws {
        for e in try fs.ReadDir(dir) {
            if e.Kind == .directory {
                if pkg == "js" && (e.Name == "cmd" || e.Name == "tests") { continue }
                if e.Name.hasPrefix(".") { continue }
                try visit(e.Path, pkg + "/" + e.Name)
            } else if e.Name.hasSuffix(".vs") {
                var list = packages[pkg] ?? []
                for i in imports(try fs.ReadText(e.Path)) where !list.contains(i) { list.append(i) }
                packages[pkg] = list
            }
        }
    }
    do {
        try visit(fs.Path("."), "js")
    } catch {
        print("check-deps: \(error)")
        return 2
    }
    var violations = 0
    for pkg in packages.keys.sorted() {
        guard let rule = ruleFor(pkg) else {
            print("VIOLATION: \(pkg) has no layering rule")
            violations += 1
            continue
        }
        for imp in packages[pkg]! {
            if imp == "web" || imp.hasPrefix("web/") {
                print("VIOLATION: \(pkg) imports \(imp): the engine knows nothing of the web")
                violations += 1
            } else if (imp == "js" || imp.hasPrefix("js/")) && !permits(rule, imp) {
                print("VIOLATION: \(pkg) imports \(imp)")
                violations += 1
            }
        }
    }
    if violations > 0 {
        print("\(violations) layering violations")
        return 1
    }
    print("ok: \(packages.count) packages follow the layering")
    return 0
}
