// vjs runs a JavaScript file with the js engine, like `node file.js`:
// it is how the engine is tested.
//
//     vsc run vjs -- file.js
package main

import (
    "fs"
    "js"
    "js/object"
)

func main() -> int32 {
    let args = CommandLine.arguments
    if args.count < 2 {
        print("usage: vjs file.js")
        return 2
    }
    let path = args[1]
    guard let source = try? fs.ReadText(fs.Path(path)) else {
        print("vjs: cannot read \(path)")
        return 2
    }
    let rt = js.Runtime()
    rt.DefineConsole { line in print(line) }
    // Report what a browser's console would: an exception thrown out of a
    // job, and a promise still rejected with no handler once jobs drain.
    var status: int32 = 0
    var unhandled: [object.JSObject] = []
    rt.Agent.OnJobError = { v in
        print("Uncaught \(js.Exception(v).Message)")
        status = 1
    }
    rt.Agent.OnRejectionTracker = { p, handled in
        if handled {
            unhandled.removeAll(where: { $0 === p })
        } else {
            unhandled.append(p)
        }
    }
    do {
        _ = try rt.Evaluate(source, filename: path)
        rt.RunJobs()
        for p in unhandled {
            if let po = p as? object.PromiseObject {
                print("Uncaught (in promise) \(js.Exception(po.Result).Message)")
                status = 1
            }
        }
        return status
    } catch let e as js.Exception {
        print("Uncaught \(e.Message)")
        return 1
    } catch {
        print("vjs: \(error)")
        return 1
    }
    return 0
}
