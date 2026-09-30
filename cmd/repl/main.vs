// repl reads JavaScript a line at a time, runs it in one runtime, and
// prints each line's completion value; promise jobs run after each line.
//
//     vsc run ./cmd/repl
package main

import (
    "js"
    "js/object"
)

/// show prints a value as a console would: strings quoted, the rest by
/// their string conversion or description.
func show(_ v: object.Value) -> string {
    switch v {
    case .string(let s):
        return "'" + s.String + "'"
    case .object, .symbol:
        return object.Describe(v)
    default:
        return (try? object.ToString(v).String) ?? object.Describe(v)
    }
}

func main() -> int32 {
    let rt = js.Runtime()
    rt.DefineConsole { line in print(line) }
    rt.Agent.OnJobError = { v in print("Uncaught \(js.Exception(v).Message)") }
    print("js -- an empty line or end of input quits")
    while true {
        print("> ", terminator: "")
        guard let line = readLine(), !line.isEmpty else { break }
        do {
            let v = try rt.Evaluate(line, filename: "<repl>")
            rt.RunJobs()
            print(show(v))
        } catch let e as js.Exception {
            print("Uncaught \(e.Message)")
        } catch {
            print("error: \(error)")
        }
    }
    return 0
}
