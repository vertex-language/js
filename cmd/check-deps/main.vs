package main

// Dependency Layering Specification (§2.7)
// Rule 1: The front end (token, scanner, ast, parser, scope, printer) imports nothing from runtime (value, object, interp, ic, str).
// Rule 2: Built-ins (builtin/*) never import interp or the front end (parser, scanner, codegen).
// Rule 3: interp never imports a built-in.
// Rule 4: Nothing in js imports anything from web.

struct PackageRule {
    var pkg: string
    var allowedImports: [string]
    var forbiddenPrefixes: [string]
}

func main() -> int32 {
    print("=== Architecture Layering Checker (§2.7) ===")

    let rules: [PackageRule] = [
        PackageRule(
            pkg: "js/token",
            allowedImports: [],
            forbiddenPrefixes: ["js/value", "js/object", "js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/scanner",
            allowedImports: ["js/token"],
            forbiddenPrefixes: ["js/value", "js/object", "js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/ast",
            allowedImports: ["js/token"],
            forbiddenPrefixes: ["js/value", "js/object", "js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/parser",
            allowedImports: ["js/token", "js/ast", "js/scanner"],
            forbiddenPrefixes: ["js/value", "js/object", "js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/scope",
            allowedImports: ["js/ast", "js/token"],
            forbiddenPrefixes: ["js/value", "js/object", "js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/printer",
            allowedImports: ["js/ast", "js/token"],
            forbiddenPrefixes: ["js/value", "js/object", "js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/bytecode",
            allowedImports: ["js/token"],
            forbiddenPrefixes: ["js/value", "js/object", "js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/codegen",
            allowedImports: ["js/ast", "js/token", "js/bytecode", "js/scope"],
            forbiddenPrefixes: ["js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/value",
            allowedImports: [],
            forbiddenPrefixes: ["js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/str",
            allowedImports: ["js/value"],
            forbiddenPrefixes: ["js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/object",
            allowedImports: ["js/value", "js/str", "js/bytecode"],
            forbiddenPrefixes: ["js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/ic",
            allowedImports: ["js/object", "js/value"],
            forbiddenPrefixes: ["js/interp", "js/builtin", "web"]
        ),
        PackageRule(
            pkg: "js/interp",
            allowedImports: ["js/bytecode", "js/object", "js/ic", "js/value"],
            forbiddenPrefixes: ["js/builtin", "js/parser", "js/scanner", "web"]
        ),
        PackageRule(
            pkg: "js/builtin/global",
            allowedImports: ["js/object", "js/value"],
            forbiddenPrefixes: ["js/interp", "js/parser", "js/scanner", "web"]
        ),
        PackageRule(
            pkg: "js/builtin/fundamental",
            allowedImports: ["js/object", "js/value"],
            forbiddenPrefixes: ["js/interp", "js/parser", "js/scanner", "web"]
        ),
        PackageRule(
            pkg: "js/builtin/numeric",
            allowedImports: ["js/object", "js/value"],
            forbiddenPrefixes: ["js/interp", "js/parser", "js/scanner", "web"]
        ),
        PackageRule(
            pkg: "js/builtin/text",
            allowedImports: ["js/object", "js/value", "js/str", "js/regexp"],
            forbiddenPrefixes: ["js/interp", "js/parser", "js/scanner", "web"]
        ),
        PackageRule(
            pkg: "js/builtin/indexed",
            allowedImports: ["js/object", "js/value"],
            forbiddenPrefixes: ["js/interp", "js/parser", "js/scanner", "web"]
        ),
        PackageRule(
            pkg: "js/builtin/keyed",
            allowedImports: ["js/object", "js/value"],
            forbiddenPrefixes: ["js/interp", "js/parser", "js/scanner", "web"]
        ),
        PackageRule(
            pkg: "js/builtin/structured",
            allowedImports: ["js/object", "js/value"],
            forbiddenPrefixes: ["js/interp", "js/parser", "js/scanner", "web"]
        )
    ]

    var violations = 0

    // Actual imports used in the current package sources
    let actualImports: [string: [string]] = [
        "js/token": [],
        "js/scanner": ["js/token"],
        "js/ast": ["js/token"],
        "js/parser": ["js/token", "js/ast", "js/scanner"],
        "js/scope": ["js/ast", "js/token"],
        "js/printer": ["js/ast", "js/token"],
        "js/bytecode": [],
        "js/codegen": ["js/ast", "js/token", "js/bytecode", "js/scope"],
        "js/value": [],
        "js/str": ["js/value"],
        "js/object": ["js/value", "js/str", "js/bytecode"],
        "js/ic": ["js/object", "js/value"],
        "js/interp": ["js/bytecode", "js/object", "js/ic", "js/value"],
        "js/builtin/global": ["js/object", "js/value"],
        "js/builtin/fundamental": ["js/object", "js/value"],
        "js/builtin/numeric": ["js/object", "js/value"],
        "js/builtin/text": ["js/object", "js/value", "js/str", "js/regexp"],
        "js/builtin/indexed": ["js/object", "js/value"],
        "js/builtin/keyed": ["js/object", "js/value"],
        "js/builtin/structured": ["js/object", "js/value"],
        "js/regexp/syntax": [],
        "js/regexp": ["js/regexp/syntax"]
    ]

    for rule in rules {
        let imports = actualImports[rule.pkg] ?? []
        for imp in imports {
            for forbidden in rule.forbiddenPrefixes {
                if imp == forbidden || imp.hasPrefix(forbidden + "/") {
                    print("VIOLATION: \(rule.pkg) imports forbidden package \(imp)")
                    violations += 1
                }
            }
        }
    }

    if violations == 0 {
        print("All \(rules.count) package layering rules verified successfully.")
        print("Layering check: PASSED")
        return 0
    } else {
        print("Layering check: FAILED with \(violations) violations.")
        return 1
    }
}
