package main

import (
    "js"
    "js/scanner"
    "js/parser"
    "js/codegen"
    "js/bytecode"
    "js/printer"
)

func runReplSession() {
    let realm = js.Realm()

    print("Vertex JavaScript Engine REPL")
    print("Type JavaScript code to evaluate, or commands: :help, :tokens <code>, :ast <code>, :dis <code>\n")

    let demoLines = [
        "1 + 2 * 3",
        "let x = [10, 20, 30]; x.push(40); x.join(',')",
        "function square(n) { return n * n; } square(8)",
        "JSON.stringify({ language: 'Vertex', fast: true })"
    ]

    for line in demoLines {
        print("> \(line)")
        do {
            let res = try realm.Eval(line)
            print("= \(res.ToString())")
        } catch {
            print("Error: \(error)")
        }
    }
}

func main() -> int32 {
    runReplSession()
    return 0
}
