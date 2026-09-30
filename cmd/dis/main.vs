// dis compiles a JavaScript file and prints its bytecode, and the
// bytecode of every function in it.
//
//     vsc run ./cmd/dis -- file.js
package main

import (
    "fs"
    "js"
    "js/bytecode"
)

func main() -> int32 {
    let args = CommandLine.arguments
    if args.count < 2 {
        print("usage: dis file.js")
        return 2
    }
    guard let source = try? fs.ReadText(fs.Path(args[1])) else {
        print("dis: cannot read \(args[1])")
        return 2
    }
    do {
        let t = try js.Runtime().Compile(source, filename: args[1])
        print(bytecode.Disassemble(t))
        return 0
    } catch let e as js.Exception {
        print(e.Message)
        return 1
    } catch {
        print("dis: \(error)")
        return 1
    }
}
