package main

import (
    "js"
    "js/value"
)

func main() -> int32 {
    print("=== JavaScript for Vertex: Embedded Engine Example ===\n")

    // 1. Initialize a new isolated JavaScript Realm with standard intrinsics and GC heap
    let realm = js.Realm()

    // 2. Register a native host function callable from JavaScript: hostLog(...args)
    realm.DefineFunction("hostLog") { args in
        var out = ""
        for i in 0..<args.count {
            if i > 0 { out += " " }
            out += args[i].ToString()
        }
        print("[Host log] " + out)
        return value.Value.Undefined
    }

    // 3. Register another host function returning values: hostAdd(a, b)
    realm.DefineFunction("hostAdd") { args in
        let a = args.count > 0 ? args[0].ToNumber() : 0.0
        let b = args.count > 1 ? args[1].ToNumber() : 0.0
        return value.Value.Number(a + b)
    }

    // 4. Inject a native JSObject directly into globalThis
    let configObj = realm.NewObject()
    configObj.Set("appName", value.Value.String("VertexApp"))
    configObj.Set("version", value.Value.Int(1))
    configObj.Set("debugMode", value.Value.Boolean(true))
    realm.Global.Set("AppConfig", value.Value.Object(configObj))

    // 5. Execute JavaScript script interacting with host functions and configuration
    let script = """
    hostLog("Starting script execution inside Realm...");
    hostLog("Configured application:", AppConfig.appName, "v" + AppConfig.version);

    // Perform arithmetic and array processing
    let sum = hostAdd(15, 27);
    hostLog("Result of hostAdd(15, 27):", sum);

    let items = [10, 20, 30];
    items.push(sum);
    hostLog("Items array:", items.join(" -> "));

    // WeakMap and GC demonstration
    let cache = new WeakMap();
    let key = { id: 42 };
    cache.set(key, { payload: "Secret Data" });
    hostLog("WeakMap cache lookup:", JSON.stringify(cache.get(key)));

    // Return final result to host
    JSON.stringify({ status: "success", count: items.length, total: sum });
    """

    do {
        let result = try realm.Eval(script)
        print("\nJavaScript execution completed successfully!")
        print("Final evaluated result:\n" + result.ToString())
        return 0
    } catch {
        print("JavaScript runtime error: \(error)")
        return 1
    }
}
