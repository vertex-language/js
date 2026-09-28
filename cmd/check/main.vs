package main

import (
    "js"
    "js/token"
    "js/scanner"
    "js/ast"
    "js/parser"
    "js/scope"
    "js/printer"
    "js/bytecode"
    "js/codegen"
    "js/value"
    "js/str"
    "js/object"
    "js/regexp"
)

var failures = 0

func check(_ ok: bool, _ msg: string) {
    if ok {
        print("ok    \(msg)")
    } else {
        print("FAIL  \(msg)")
        failures += 1
    }
}

func main() -> int32 {
    print("=== Testing js repo packages ===")

    // 1. Token & Scanner
    testScanner()

    // 2. Parser & AST
    testParser()

    // 3. Printer
    testPrinter()

    // 4. Scope
    testScope()

    // 5. Bytecode & Codegen
    testBytecode()

    // 6. Values & Strings
    testValuesAndStrings()

    // 7. Objects & Shapes
    testObjectsAndShapes()

    // 8. Regexp
    testRegExp()

    // 9. Runtime Evaluation (VM & Built-ins)
    testEvaluation()

    // 10. Garbage Collection & Memory Primitives
    testGarbageCollectionAndMemoryPrimitives()

    // 11. Control Abstraction & Promises
    testControlAndPromises()

    // 12. Structured Binary Data & TypedArrays
    testBinaryDataAndTypedArrays()

    // 14. Modern Syntax Features (Rest, Spread, Template Literals)
    testModernSyntaxFeatures()

    // 15. ECMAScript 2023-2026 Built-ins (Change Array by Copy, withResolvers, groupBy, Set Methods)
    testECMAScript2024To2026Builtins()

    print("\nSummary: \(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")")
    return failures == 0 ? 0 : 1
}

func testScanner() {
    let src = "let x = 42 + 0x10; if (x === 58) { return 'hello\\n'; }"
    let sc = scanner.Scanner(source: src)

    let t1 = sc.Next()
    check(t1.Kind == .kLet, "scanner: token let")

    let t2 = sc.Next()
    check(t2.Kind == .identifier && t2.Text == "x", "scanner: identifier x")

    let t3 = sc.Next()
    check(t3.Kind == .assign, "scanner: token =")

    let t4 = sc.Next()
    check(t4.Kind == .number && t4.Text == "42", "scanner: number 42")

    let t5 = sc.Next()
    check(t5.Kind == .add, "scanner: operator +")

    let t6 = sc.Next()
    check(t6.Kind == .number && t6.Text == "0x10", "scanner: hex number 0x10")
}

func testParser() {
    do {
        let prog = try parser.ParseScript("let total = 0; for (let i = 0; i < 5; i++) { total += i; }")
        check(prog.Body.count == 2, "parser: parsed statement count")
        if case .varDecl(let v) = prog.Body[0] {
            check(v.Kind == "let" && v.Declarations[0].Id == "total", "parser: let total declaration")
        } else {
            check(false, "parser: expected varDecl")
        }
        if case .forStmt = prog.Body[1] {
            check(true, "parser: parsed for statement")
        } else {
            check(false, "parser: expected forStmt")
        }
    } catch {
        check(false, "parser error: \(error)")
    }
}

func testPrinter() {
    do {
        let prog = try parser.ParseScript("function add(a, b) {\n  return a + b;\n}\n")
        let printed = printer.Print(prog)
        check(printed.contains("function add(a, b)"), "printer: printed function header")
        check(printed.contains("return (a + b);"), "printer: printed return expression")
    } catch {
        check(false, "printer error: \(error)")
    }
}

func testScope() {
    do {
        let prog = try parser.ParseScript("let a = 1; { let b = 2; }")
        let globalScope = try scope.Analyze(prog)
        check(globalScope.Lookup("a") != nil, "scope: global variable a found")
        check(globalScope.Lookup("b") == nil, "scope: block-scoped variable b not in global scope")
    } catch {
        check(false, "scope error: \(error)")
    }

    // Duplicate lexical declaration error test
    do {
        let prog = try parser.ParseScript("let x = 1; let x = 2;")
        _ = try scope.Analyze(prog)
        check(false, "scope: expected duplicate let declaration error")
    } catch {
        check(true, "scope: detected duplicate let declaration")
    }
}

func testBytecode() {
    do {
        let prog = try parser.ParseScript("let x = 10 + 20;")
        let code = try codegen.Compile(prog)
        check(code.Instructions.count > 0, "codegen: instructions generated")
        let dis = bytecode.Disassemble(code)
        check(dis.contains("Add"), "bytecode: disassembler contains Add opcode")
    } catch {
        check(false, "bytecode error: \(error)")
    }
}

func testValuesAndStrings() {
    let vUndef = value.Value.Undefined
    let vNull = value.Value.Null
    let vTrue = value.Value.True
    let vInt = value.Value.Int(42)
    let vStr = value.Value.String("hello")

    check(!vUndef.ToBoolean(), "value: undefined toBoolean is false")
    check(!vNull.ToBoolean(), "value: null toBoolean is false")
    check(vTrue.ToBoolean(), "value: true toBoolean is true")
    check(vInt.ToBoolean(), "value: non-zero int toBoolean is true")
    check(vInt.ToInt32() == 42, "value: toInt32 is 42")
    check(vStr.ToString() == "hello", "value: toString is hello")

    // String operations
    let jsStr = str.JSString.FromUTF8("VertexJS")
    check(jsStr.Length == 8, "str: length is 8")
    check(jsStr.ToUTF8() == "VertexJS", "str: toUTF8 matches input")
    let sub = jsStr.Substring(start: 0, end: 6)
    check(sub.ToUTF8() == "Vertex", "str: substring 0..6 is Vertex")
}

func testObjectsAndShapes() {
    let r = object.Realm()
    let obj = r.NewObject()
    obj.Set("answer", value.Value.Int(42))
    check(obj.Get("answer").ToInt32() == 42, "object: get property after set")
    check(obj.Has("answer"), "object: has property")
    check(!obj.Has("nonExistent"), "object: does not have missing property")

    let arr = r.NewArray()
    arr.SetElement(0, value.Value.String("first"))
    arr.SetElement(1, value.Value.String("second"))
    check(arr.GetElement(0).ToString() == "first", "object: array element 0")
    check(arr.Get("length").ToInt32() == 2, "object: array length is 2")
}

func testRegExp() {
    do {
        let re = try regexp.RegExp.Compile("^hello.*world$")
        check(re.Test("hello beautiful world"), "regexp: pattern matches text")
        check(!re.Test("goodbye world"), "regexp: pattern does not match wrong text")
    } catch {
        check(false, "regexp error: \(error)")
    }
}

func testEvaluation() {
    let agent = js.Agent()
    let realm = agent.NewRealm()

    // Simple arithmetic
    do {
        let res = try realm.Eval("10 + 20 * 2;")
        check(res.ToInt32() == 50, "eval: arithmetic precedence 10 + 20 * 2 = 50")
    } catch {
        check(false, "eval arithmetic error: \(error)")
    }

    // Variables and control flow
    do {
        let script = """
        let sum = 0;
        let i = 1;
        while (i <= 10) {
            sum += i;
            i++;
        }
        sum;
        """
        let res = try realm.Eval(script)
        check(res.ToInt32() == 55, "eval: while loop sum 1..10 = 55")
    } catch {
        check(false, "eval loop error: \(error)")
    }

    // Function declaration and call
    do {
        let script = """
        function factorial(n) {
            if (n <= 1) {
                return 1;
            }
            return n * factorial(n - 1);
        }
        factorial(5);
        """
        let res = try realm.Eval(script)
        check(res.ToInt32() == 120, "eval: recursive factorial(5) = 120")
    } catch {
        check(false, "eval recursion error: \(error)")
    }

    // Built-ins: Math, parseInt, Array
    do {
        let res = try realm.Eval("Math.abs(-42) + parseInt('8');")
        check(res.ToInt32() == 50, "eval: Math.abs(-42) + parseInt('8') = 50")
    } catch {
        check(false, "eval builtins error: \(error)")
    }

    // Array manipulation
    do {
        let script = """
        let arr = [1, 2, 3];
        arr.push(4);
        arr.join("-");
        """
        let res = try realm.Eval(script)
        check(res.ToString() == "1-2-3-4", "eval: array push and join = '1-2-3-4'")
    } catch {
        check(false, "eval array error: \(error)")
    }

    // JSON stringify & parse
    do {
        let script = """
        let obj = { x: 10, y: "ok" };
        JSON.stringify(obj);
        """
        let res = try realm.Eval(script)
        check(res.ToString() == "{\"x\":10,\"y\":\"ok\"}", "eval: JSON.stringify produces expected string")
    } catch {
        check(false, "eval JSON error: \(error)")
    }

    // Native host function injection
    realm.DefineFunction("hostMultiply") { args in
        let a = args.count > 0 ? args[0].ToNumber() : 0.0
        let b = args.count > 1 ? args[1].ToNumber() : 0.0
        return value.Value.Number(a * b)
    }

    do {
        let res = try realm.Eval("hostMultiply(6, 7);")
        check(res.ToInt32() == 42, "eval: native host function hostMultiply(6, 7) = 42")
    } catch {
        check(false, "eval host function error: \(error)")
    }
}

// 10. Garbage Collection & Memory Primitives
func testGarbageCollectionAndMemoryPrimitives() {
    let realm = js.Realm()

    // 10.1 Verify gc() built-in callable from JS
    do {
        let res = try realm.Eval("gc(); 100;")
        check(res.ToInt32() == 100, "gc: gc() built-in executes without error")
    } catch {
        check(false, "gc error: \(error)")
    }

    // 10.2 Verify cyclic reference collection
    do {
        _ = try realm.Eval("""
        function createCycle() {
            let a = { name: "A" };
            let b = { name: "B" };
            a.child = b;
            b.child = a;
            return 1;
        }
        """)
        let beforeCount = realm.Heap.LiveObjectCount
        _ = try realm.Eval("createCycle();")
        let afterAllocCount = realm.Heap.LiveObjectCount
        check(afterAllocCount > beforeCount, "gc: allocated cyclic objects")

        // Trigger GC to collect the unreferenced cycle
        realm.GC()
        let afterGCCount = realm.Heap.LiveObjectCount
        check(afterGCCount == beforeCount, "gc: cyclic reference cleanly collected by GC")
    } catch {
        check(false, "gc cycle test error: \(error)")
    }

    // 10.3 WeakMap functionality & Ephemeron semantics
    do {
        let script = """
        let wm = new WeakMap();
        let key = { id: 42 };
        wm.set(key, 999);
        let hasBefore = wm.has(key);
        let valBefore = wm.get(key);
        wm.delete(key);
        let hasAfter = wm.has(key);
        let valAfter = wm.get(key);
        hasBefore && (valBefore === 999) && !hasAfter && (valAfter === undefined);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "weakmap: set, get, has, delete operations pass")
    } catch {
        check(false, "weakmap error: \(error)")
    }

    // 10.4 WeakSet functionality
    do {
        let script = """
        let ws = new WeakSet();
        let item = { label: "alpha" };
        ws.add(item);
        let hasItem = ws.has(item);
        ws.delete(item);
        let hasItemAfter = ws.has(item);
        hasItem && !hasItemAfter;
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "weakset: add, has, delete operations pass")
    } catch {
        check(false, "weakset error: \(error)")
    }

    // 10.5 WeakRef deref
    do {
        let script = """
        let obj = { message: "retained" };
        let wr = new WeakRef(obj);
        let derefObj = wr.deref();
        (derefObj !== undefined) && (derefObj.message === "retained");
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "weakref: deref returns target object while alive")
    } catch {
        check(false, "weakref error: \(error)")
    }

    // 10.6 FinalizationRegistry register and unregister
    do {
        let script = """
        let fr = new FinalizationRegistry(function(token) {});
        let target = { name: "targetObj" };
        let token = { id: "token123" };
        fr.register(target, 42, token);
        let unregistered = fr.unregister(token);
        unregistered;
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "finalizer: register and unregister return true")
    } catch {
        check(false, "finalizer error: \(error)")
    }
}

func testControlAndPromises() {
    let realm = js.Realm()

    // 11.1 Promise.resolve and .then
    do {
        _ = try realm.Eval("""
        var out = 0;
        Promise.resolve(42).then(function(v) {
            out = v;
        });
        """)
        let res = try realm.Eval("out;")
        check(res.ToInt32() == 42, "promise: Promise.resolve and .then update state to 42")
    } catch {
        check(false, "promise resolve error: \(error)")
    }

    // 11.2 new Promise constructor with asynchronous executor resolution
    do {
        _ = try realm.Eval("""
        var outcome = "";
        let p = new Promise(function(resolve, reject) {
            resolve("resolved_value");
        });
        p.then(function(val) {
            outcome = val;
        });
        """)
        let res = try realm.Eval("outcome;")
        check(res.ToString() == "resolved_value", "promise: constructor resolution propagates to .then")
    } catch {
        check(false, "promise constructor error: \(error)")
    }

    // 11.3 Promise chaining (.then -> .then)
    do {
        _ = try realm.Eval("""
        var chained = 0;
        Promise.resolve(10)
            .then(function(x) { return x * 2; })
            .then(function(y) { chained = y + 5; });
        """)
        let res = try realm.Eval("chained;")
        check(res.ToInt32() == 25, "promise: promise chaining 10 * 2 + 5 = 25")
    } catch {
        check(false, "promise chaining error: \(error)")
    }

    // 11.4 Promise rejection and .catch recovery
    do {
        _ = try realm.Eval("""
        var recovered = "";
        Promise.reject("original_error")
            .catch(function(err) {
                return "recovered_from_" + err;
            })
            .then(function(res) {
                recovered = res;
            });
        """)
        let res = try realm.Eval("recovered;")
        check(res.ToString() == "recovered_from_original_error", "promise: rejection handled and recovered via .catch")
    } catch {
        check(false, "promise catch error: \(error)")
    }

    // 11.5 Promise.all
    do {
        _ = try realm.Eval("""
        var allResult = "";
        Promise.all([Promise.resolve("A"), Promise.resolve("B"), Promise.resolve("C")])
            .then(function(arr) {
                allResult = arr.join("-");
            });
        """)
        let res = try realm.Eval("allResult;")
        check(res.ToString() == "A-B-C", "promise: Promise.all resolves all items in order")
    } catch {
        check(false, "promise.all error: \(error)")
    }

    // 11.6 Promise.race
    do {
        _ = try realm.Eval("""
        var raceWinner = "";
        Promise.race([Promise.resolve("first"), Promise.resolve("second")])
            .then(function(winner) {
                raceWinner = winner;
            });
        """)
        let res = try realm.Eval("raceWinner;")
        check(res.ToString() == "first", "promise: Promise.race resolves with the first settled item")
    } catch {
        check(false, "promise.race error: \(error)")
    }

    // 11.7 queueMicrotask
    do {
        _ = try realm.Eval("""
        var microtaskRun = false;
        queueMicrotask(function() {
            microtaskRun = true;
        });
        """)
        let res = try realm.Eval("microtaskRun;")
        check(res.ToBoolean(), "microtask: queueMicrotask executes after script finishes")
    } catch {
        check(false, "queueMicrotask error: \(error)")
    }
}

func testBinaryDataAndTypedArrays() {
    let realm = js.Realm()

    // 12.1 ArrayBuffer and slice
    do {
        let script = """
        let ab = new ArrayBuffer(16);
        let slice = ab.slice(4, 12);
        ab.byteLength === 16 && slice.byteLength === 8;
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "arraybuffer: byteLength and slice behave per specification")
    } catch {
        check(false, "arraybuffer error: \(error)")
    }

    // 12.2 DataView reads and writes
    do {
        let script = """
        let ab = new ArrayBuffer(8);
        let dv = new DataView(ab);
        dv.setUint8(0, 255);
        dv.setInt16(1, -1000, true);
        (dv.getUint8(0) === 255) && (dv.getInt16(1, true) === -1000);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "dataview: multi-endian get/setUint8 and get/setInt16 pass")
    } catch {
        check(false, "dataview error: \(error)")
    }

    // 12.3 Uint8Array indexed read and write
    do {
        let script = """
        let u8 = new Uint8Array(4);
        u8[0] = 10;
        u8[1] = 20;
        u8[0] + u8[1] === 30 && u8.length === 4 && u8.byteLength === 4;
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "typedarray: Uint8Array indexed element read and write pass")
    } catch {
        check(false, "uint8array error: \(error)")
    }

    // 12.4 Uint8ClampedArray clamping semantics
    do {
        let script = """
        let clamped = new Uint8ClampedArray(3);
        clamped[0] = 300;
        clamped[1] = -50;
        clamped[2] = 127.6;
        clamped[0] === 255 && clamped[1] === 0 && clamped[2] === 128;
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "typedarray: Uint8ClampedArray clamping and rounding pass")
    } catch {
        check(false, "uint8clampedarray error: \(error)")
    }

    // 12.5 Float32Array & Float64Array
    do {
        let script = """
        let f32 = new Float32Array(2);
        f32[0] = 3.5;
        let f64 = new Float64Array(1);
        f64[0] = 123456.789;
        (f32[0] === 3.5) && (f64[0] === 123456.789);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "typedarray: Float32Array and Float64Array float precision pass")
    } catch {
        check(false, "float array error: \(error)")
    }

    // 12.6 Shared ArrayBuffer across views
    do {
        let script = """
        let ab = new ArrayBuffer(4);
        let u8 = new Uint8Array(ab);
        let u32 = new Uint32Array(ab);
        u8[0] = 1;
        u8[1] = 0;
        u8[2] = 0;
        u8[3] = 0;
        u32[0] === 1;
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "typedarray: shared ArrayBuffer reflected across distinct views")
    } catch {
        check(false, "shared buffer error: \(error)")
    }

    // 12.7 ArrayBuffer.isView
    do {
        let script = """
        let ab = new ArrayBuffer(8);
        let u8 = new Uint8Array(ab);
        let dv = new DataView(ab);
        ArrayBuffer.isView(u8) && ArrayBuffer.isView(dv) && !ArrayBuffer.isView(ab);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "arraybuffer: ArrayBuffer.isView correctly identifies views")
    } catch {
        check(false, "isView error: \(error)")
    }

    // 13.1 Class declaration and instantiation (§15)
    do {
        let script = """
        class Person {
            constructor(name) {
                this.name = name;
            }
            greet() {
                return "Hello " + this.name;
            }
        }
        let p = new Person("Ada");
        (p.greet() === "Hello Ada") && (p instanceof Person);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "class: declaration, constructor, methods, and instanceof pass")
    } catch {
        check(false, "class declaration error: \(error)")
    }

    // 13.2 Class inheritance, super constructor, super method calls (§15)
    do {
        let script = """
        class Animal {
            constructor(name) {
                this.name = name;
            }
            sound() {
                return "Sound";
            }
        }
        class Cat extends Animal {
            constructor(name, lives) {
                super(name);
                this.lives = lives;
            }
            sound() {
                return super.sound() + "->Meow";
            }
        }
        let c = new Cat("Whiskers", 9);
        (c.name === "Whiskers") && (c.lives === 9) && (c.sound() === "Sound->Meow") && (c instanceof Cat) && (c instanceof Animal) && (c instanceof Object);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "class: inheritance, super(), super.method(), and prototype chain pass")
    } catch {
        check(false, "class inheritance error: \(error)")
    }

    // 13.3 Static methods and static inheritance
    do {
        let script = """
        class BaseMath {
            static add(a, b) {
                return a + b;
            }
        }
        class SubMath extends BaseMath {
            static mul(a, b) {
                return a * b;
            }
        }
        (BaseMath.add(10, 20) === 30) && (SubMath.mul(3, 4) === 12) && (SubMath.add(5, 7) === 12);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "class: static methods and static inheritance pass")
    } catch {
        check(false, "class static error: \(error)")
    }

    // 13.4 Class expressions
    do {
        let script = """
        let Anon = class {
            constructor(val) {
                this.val = val;
            }
            calc() {
                return this.val * 3;
            }
        };
        let a = new Anon(14);
        (a.calc() === 42) && (a instanceof Anon);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "class: class expressions and anonymous classes pass")
    } catch {
        check(false, "class expression error: \(error)")
    }

    // 13.5 Object.create and Object.setPrototypeOf / getPrototypeOf
    do {
        let script = """
        let proto = { x: 100 };
        let obj = Object.create(proto);
        let sameProto = (Object.getPrototypeOf(obj) === proto);
        let newProto = { y: 200 };
        Object.setPrototypeOf(obj, newProto);
        sameProto && (obj.y === 200) && (Object.getPrototypeOf(obj) === newProto);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "object: Object.create, setPrototypeOf, getPrototypeOf pass")
    } catch {
        check(false, "Object prototype helpers error: \(error)")
    }

    // 13.6 Timers: setTimeout and clearTimeout
    do {
        _ = try realm.Eval("""
        var timerFired = 0;
        var cancelledFired = 0;
        setTimeout(function() {
            timerFired = 42;
        }, 10);
        let cancelId = setTimeout(function() {
            cancelledFired = 1;
        }, 10);
        clearTimeout(cancelId);
        """)
        realm.RunJobs()
        let res = try realm.Eval("(timerFired === 42) && (cancelledFired === 0);")
        check(res.ToBoolean(), "timer: setTimeout schedules job and clearTimeout cancels job")
    } catch {
        check(false, "timer error: \(error)")
    }
}

func testModernSyntaxFeatures() {
    let realm = js.Realm()

    // 14.1 Rest parameter in function declaration
    do {
        let script = """
        function sumWithMultiplier(multiplier, ...nums) {
            let total = 0;
            for (let i = 0; i < nums.length; i = i + 1) {
                total = total + nums[i];
            }
            return total * multiplier;
        }
        sumWithMultiplier(2, 1, 2, 3, 4) === 20;
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "syntax: rest parameter in function declaration packs arguments into Array")
    } catch {
        check(false, "rest param in functionDecl error: \(error)")
    }

    // 14.2 Rest parameter in arrow function
    do {
        let script = """
        let countArgs = (...args) => args.length;
        countArgs(10, 20, 30, 40) === 4;
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "syntax: rest parameter in arrow function works as expected")
    } catch {
        check(false, "rest param in arrow error: \(error)")
    }

    // 14.3 Array spread
    do {
        let script = """
        let base = [2, 3];
        let combined = [1, ...base, 4, 5];
        (combined.length === 5) && (combined[0] === 1) && (combined[1] === 2) && (combined[2] === 3) && (combined[3] === 4) && (combined[4] === 5);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "syntax: array literal spread expands iterable elements")
    } catch {
        check(false, "array spread error: \(error)")
    }

    // 14.4 Function call with spread arguments
    do {
        let script = """
        function add3(a, b, c) {
            return a + b + c;
        }
        let items = [10, 20, 30];
        add3(...items) === 60;
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "syntax: call with spread passes unpacked array elements")
    } catch {
        check(false, "call spread error: \(error)")
    }

    // 14.5 Object spread
    do {
        let script = """
        let p1 = { a: 1, b: 2 };
        let p2 = { ...p1, c: 3, b: 20 };
        (p2.a === 1) && (p2.b === 20) && (p2.c === 3);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "syntax: object literal spread copies own enumerable properties")
    } catch {
        check(false, "object spread error: \(error)")
    }

    // 14.6 Template literal interpolation
    do {
        let script = """
        let name = "World";
        let msg = `Hello, ${name}! Sum is ${5 * 8 + 2}.`;
        msg === "Hello, World! Sum is 42.";
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "syntax: template literal evaluates and interpolates expressions")
    } catch {
        check(false, "template interpolation error: \(error)")
    }
}

func testECMAScript2024To2026Builtins() {
    let realm = js.Realm()

    // 15.1 Promise.withResolvers (ECMAScript 2024)
    do {
        _ = try realm.Eval("""
        var withResFired = 0;
        let res = Promise.withResolvers();
        res.promise.then(function(val) {
            withResFired = val;
        });
        res.resolve(99);
        """)
        realm.RunJobs()
        let res = try realm.Eval("withResFired === 99;")
        check(res.ToBoolean(), "promise: Promise.withResolvers() produces promise and resolvers")
    } catch {
        check(false, "Promise.withResolvers error: \(error)")
    }

    // 15.2 Object.groupBy (ECMAScript 2024)
    do {
        let script = """
        let inventory = [
            { name: "asparagus", type: "vegetables" },
            { name: "bananas", type: "fruit" },
            { name: "goat", type: "meat" },
            { name: "cherries", type: "fruit" },
            { name: "fish", type: "meat" }
        ];
        let result = Object.groupBy(inventory, function(item) { return item.type; });
        (result.fruit.length === 2) && (result.vegetables.length === 1) && (result.meat.length === 2);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "object: Object.groupBy groups elements by string keys")
    } catch {
        check(false, "Object.groupBy error: \(error)")
    }

    // 15.3 Object.entries, Object.fromEntries, Object.hasOwn
    do {
        let script = """
        let entries = Object.entries({ a: 1, b: 2 });
        let obj = Object.fromEntries(entries);
        (obj.a === 1) && (obj.b === 2) && Object.hasOwn(obj, "a") && !Object.hasOwn(obj, "toString");
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "object: Object.entries, fromEntries, and hasOwn pass")
    } catch {
        check(false, "Object entries/hasOwn error: \(error)")
    }

    // 15.4 Map.groupBy (ECMAScript 2024)
    do {
        let script = """
        let items = [1, 2, 3, 4, 5, 6];
        let grouped = Map.groupBy(items, function(x) { return x % 2 === 0 ? "even" : "odd"; });
        (grouped.get("even").length === 3) && (grouped.get("odd").length === 3);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "keyed: Map.groupBy groups elements into Map instance")
    } catch {
        check(false, "Map.groupBy error: \(error)")
    }

    // 15.5 ECMAScript 2025 Set methods (union, intersection, difference, symmetricDifference, isSubsetOf)
    do {
        let script = """
        let s1 = new Set(); s1.add("a"); s1.add("b");
        let s2 = new Set(); s2.add("b"); s2.add("c");
        let u = s1.union(s2);
        let inter = s1.intersection(s2);
        let diff = s1.difference(s2);
        let symm = s1.symmetricDifference(s2);
        (u.size === 3) && (inter.size === 1) && inter.has("b") && (diff.size === 1) && diff.has("a") && (symm.size === 2) && symm.has("a") && symm.has("c") && s1.isSubsetOf(u);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "keyed: Set methods union, intersection, difference, symmetricDifference pass")
    } catch {
        check(false, "Set methods error: \(error)")
    }

    // 15.6 Change Array by Copy (ECMAScript 2023)
    do {
        let script = """
        let original = [3, 1, 2];
        let rev = original.toReversed();
        let sorted = original.toSorted();
        let spliced = original.toSpliced(1, 1, 99);
        let replaced = original.with(0, 100);
        (original[0] === 3) && (rev[0] === 2) && (sorted[0] === 1) && (spliced[1] === 99) && (replaced[0] === 100);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "indexed: toReversed, toSorted, toSpliced, and with Change Array by Copy")
    } catch {
        check(false, "Change Array by Copy error: \(error)")
    }

    // 15.7 Array findLast, findLastIndex, and at
    do {
        let script = """
        let numbers = [5, 12, 50, 130, 44];
        let lastBig = numbers.findLast(function(n) { return n > 45; });
        let lastBigIdx = numbers.findLastIndex(function(n) { return n > 45; });
        let lastEl = numbers.at(-1);
        (lastBig === 130) && (lastBigIdx === 3) && (lastEl === 44);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "indexed: findLast, findLastIndex, and at search arrays correctly")
    } catch {
        check(false, "Array findLast/at error: \(error)")
    }

    // 15.8 Array.from, Array.of, and higher-order methods (map, filter, reduce)
    do {
        let script = """
        let fromArr = Array.from("abc", function(ch) { return ch + "!"; });
        let ofArr = Array.of(10, 20, 30);
        let nums = [1, 2, 3, 4];
        let doubled = nums.map(function(x) { return x * 2; });
        let evens = nums.filter(function(x) { return x % 2 === 0; });
        let sum = nums.reduce(function(acc, x) { return acc + x; }, 0);
        (fromArr.join(",") === "a!,b!,c!") && (ofArr.length === 3) && (doubled[3] === 8) && (evens.length === 2) && (sum === 10);
        """
        let res = try realm.Eval(script)
        check(res.ToBoolean(), "indexed: Array.from, of, map, filter, and reduce behave per specification")
    } catch {
        check(false, "Array higher order error: \(error)")
    }
}


