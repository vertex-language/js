// example embeds the engine as a host does: a runtime, a console, a
// native function and a host object in globalThis, a script that uses
// them, and the promise jobs it leaves.
//
//     vsc run ./cmd/example
package main

import (
    "js"
    "js/object"
)

func main() -> int32 {
    let rt = js.Runtime()
    rt.DefineConsole { line in print("[console] " + line) }

    // A native function: hostAdd(a, b).
    rt.Define("hostAdd", .object(rt.Function("hostAdd", 2) { _, args, _ in
        let a = try object.ToNumber(object.Arg(args, 0))
        let b = try object.ToNumber(object.Arg(args, 1))
        return .number(a + b)
    }))

    // A host object: AppConfig.
    let config = object.JSObject(proto: rt.Realm.ObjectPrototype)
    config.DefineData(object.Key("name"), rt.StringValue("VertexApp"))
    config.DefineData(object.Key("version"), .number(1))
    rt.Define("AppConfig", .object(config))

    let script = """
    console.log("running", AppConfig.name, "v" + AppConfig.version);
    const sum = hostAdd(15, 27);
    Promise.resolve(sum).then(v => console.log("resolved", v));
    queueMicrotask(() => console.log("microtask"));
    JSON.stringify({ status: "ok", sum });
    """
    do {
        let result = try rt.Evaluate(script, filename: "example.js")
        print("completion: " + ((try? object.ToString(result).String) ?? ""))
        rt.RunJobs()
        return 0
    } catch let e as js.Exception {
        print("Uncaught \(e.Message)")
        return 1
    } catch {
        print("example: \(error)")
        return 1
    }
}
