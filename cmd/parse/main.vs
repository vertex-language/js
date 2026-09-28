// Parses files and reports each one's first syntax error: the front end
// on its own.
//
//     vsc run parse -- file.js ...
package main

import (
    "fs"
    "js/parser"
)

func main() -> int32 {
    let args = CommandLine.arguments
    if args.count < 2 {
        print("usage: parse file.js ...")
        return 2
    }
    var failed: int32 = 0
    for i in 1..<args.count {
        let path = args[i]
        var src = ""
        do {
            src = try fs.ReadText(fs.Path(path))
        } catch {
            print("\(path): cannot read")
            failed = 1
            continue
        }
        let module = path.hasSuffix(".mjs")
        do {
            let prog = module ? try parser.ParseModule(src, filename: path) : try parser.ParseScript(src, filename: path)
            print("\(path): ok, \(prog.Body.count) statements")
        } catch let e as parser.ParseError {
            print("\(path):\(e.Line): SyntaxError: \(e.Message)")
            failed = 1
        } catch {
            print("\(path): error")
            failed = 1
        }
    }
    return failed
}
