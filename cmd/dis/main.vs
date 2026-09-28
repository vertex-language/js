package main

import (
    "js/parser"
    "js/codegen"
    "js/bytecode"
)

func main() -> int32 {
    let sampleScript = """
    function fib(n) {
        if (n <= 1) return n;
        return fib(n - 1) + fib(n - 2);
    }
    let result = fib(10);
    """

    print("=== JS Bytecode Disassembler ===")
    print("Source:\n\(sampleScript)\n")

    do {
        let prog = try parser.ParseScript(sampleScript, filename: "<sample>")
        let code = try codegen.Compile(prog)
        let dis = bytecode.Disassemble(code)
        print("Disassembly:")
        print(dis)
        return 0
    } catch {
        print("Disassembly error: \(error)")
        return 1
    }
}
