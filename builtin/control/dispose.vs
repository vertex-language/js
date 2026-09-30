package control

import (
    "js/object"
    "js/str"
    "js/value"
)

// Explicit resource management's built-ins (ES2026 §27.3, §27.4):
// DisposableStack, AsyncDisposableStack, and the iterators' dispose
// methods. They are self-hosted: classes whose private fields are the
// spec's internal slots, so a method on the wrong receiver throws the
// TypeError a brand check does. `using` itself is the compiler's.

let disposeSource = """
function (disposeSym, asyncDisposeSym, toStringTagSym, isCallable, call, makeSuppressed, defineMethodAlias) {
    "use strict";
    function check(stack) {
        if (stack.disposed) throw new ReferenceError("Cannot use a disposed stack");
    }
    function disposeAll(resources) {
        let hasError = false;
        let error;
        for (let i = resources.length - 1; i >= 0; i--) {
            const r = resources[i];
            try {
                call(r.method, r.value);
            } catch (e) {
                error = hasError ? makeSuppressed(e, error) : e;
                hasError = true;
            }
        }
        if (hasError) throw error;
    }
    class DisposableStack {
        #disposed = false;
        #resources = [];
        get disposed() { return this.#disposed; }
        use(value) {
            if (this.#disposed) throw new ReferenceError("Cannot call DisposableStack.prototype.use on a disposed DisposableStack");
            if (value !== null && value !== undefined) {
                if (typeof value !== "object" && typeof value !== "function") throw new TypeError(String(value) + " is not disposable");
                const method = value[disposeSym];
                if (!isCallable(method)) throw new TypeError("Symbol(Symbol.dispose) is not a function");
                this.#resources.push({ value, method });
            }
            return value;
        }
        adopt(value, onDispose) {
            if (this.#disposed) throw new ReferenceError("Cannot call DisposableStack.prototype.adopt on a disposed DisposableStack");
            if (!isCallable(onDispose)) throw new TypeError(String(onDispose) + " is not a function");
            this.#resources.push({ value: undefined, method: () => call(onDispose, undefined, value) });
            return value;
        }
        defer(onDispose) {
            if (this.#disposed) throw new ReferenceError("Cannot call DisposableStack.prototype.defer on a disposed DisposableStack");
            if (!isCallable(onDispose)) throw new TypeError(String(onDispose) + " is not a function");
            this.#resources.push({ value: undefined, method: onDispose });
        }
        move() {
            if (this.#disposed) throw new ReferenceError("Cannot call DisposableStack.prototype.move on a disposed DisposableStack");
            const next = new DisposableStack();
            next.#resources = this.#resources;
            this.#resources = [];
            this.#disposed = true;
            return next;
        }
        dispose() {
            if (this.#disposed) return undefined;
            this.#disposed = true;
            const resources = this.#resources;
            this.#resources = [];
            disposeAll(resources);
        }
    }
    class AsyncDisposableStack {
        #disposed = false;
        #resources = [];
        get disposed() { return this.#disposed; }
        use(value) {
            if (this.#disposed) throw new ReferenceError("Cannot call AsyncDisposableStack.prototype.use on a disposed AsyncDisposableStack");
            if (value === null || value === undefined) {
                this.#resources.push({ value: undefined, method: undefined, awaitResult: false });
                return value;
            }
            if (typeof value !== "object" && typeof value !== "function") throw new TypeError(String(value) + " is not disposable");
            let method = value[asyncDisposeSym];
            let awaitResult = true;
            if (method === undefined || method === null) {
                method = value[disposeSym];
                awaitResult = false;
            }
            if (!isCallable(method)) throw new TypeError("Symbol(Symbol.asyncDispose) is not a function");
            this.#resources.push({ value, method, awaitResult });
            return value;
        }
        adopt(value, onDisposeAsync) {
            if (this.#disposed) throw new ReferenceError("Cannot call AsyncDisposableStack.prototype.adopt on a disposed AsyncDisposableStack");
            if (!isCallable(onDisposeAsync)) throw new TypeError(String(onDisposeAsync) + " is not a function");
            this.#resources.push({ value: undefined, method: () => call(onDisposeAsync, undefined, value), awaitResult: true });
            return value;
        }
        defer(onDisposeAsync) {
            if (this.#disposed) throw new ReferenceError("Cannot call AsyncDisposableStack.prototype.defer on a disposed AsyncDisposableStack");
            if (!isCallable(onDisposeAsync)) throw new TypeError(String(onDisposeAsync) + " is not a function");
            this.#resources.push({ value: undefined, method: onDisposeAsync, awaitResult: true });
        }
        move() {
            if (this.#disposed) throw new ReferenceError("Cannot call AsyncDisposableStack.prototype.move on a disposed AsyncDisposableStack");
            const next = new AsyncDisposableStack();
            next.#resources = this.#resources;
            this.#resources = [];
            this.#disposed = true;
            return next;
        }
        async disposeAsync() {
            if (this.#disposed) return undefined;
            this.#disposed = true;
            const resources = this.#resources;
            this.#resources = [];
            let hasError = false;
            let error;
            for (let i = resources.length - 1; i >= 0; i--) {
                const r = resources[i];
                try {
                    if (r.method === undefined) {
                        await undefined;
                    } else {
                        const result = call(r.method, r.value);
                        await (r.awaitResult ? result : undefined);
                    }
                } catch (e) {
                    error = hasError ? makeSuppressed(e, error) : e;
                    hasError = true;
                }
            }
            if (hasError) throw error;
        }
    }
    defineMethodAlias(DisposableStack.prototype, "dispose", disposeSym, "DisposableStack");
    defineMethodAlias(AsyncDisposableStack.prototype, "disposeAsync", asyncDisposeSym, "AsyncDisposableStack");
    const iteratorDispose = {
        [disposeSym]() {
            const ret = this.return;
            if (ret !== undefined && ret !== null) call(ret, this);
        },
        async [asyncDisposeSym]() {
            const ret = this.return;
            if (ret !== undefined && ret !== null) await call(ret, this);
        },
    };
    return function select(which) {
        switch (which) {
            case 0: return DisposableStack;
            case 1: return AsyncDisposableStack;
            case 2: return iteratorDispose[disposeSym];
            default: return iteratorDispose[asyncDisposeSym];
        }
    };
}
"""

func installDispose(_ r: object.Realm) {
    let helpers: [Value] = [
        .symbol(value.SymDispose),
        .symbol(value.SymAsyncDispose),
        .symbol(value.SymToStringTag),
        .object(r.Function("isCallable", 1) { _, a, _ in .bool(object.Arg(a, 0).IsCallable) }),
        .object(r.Function("call", 2) { _, a, _ in
            var rest: [Value] = []
            var i = 2
            while i < a.count { rest.append(a[i]); i += 1 }
            return try object.Call(object.Arg(a, 0), object.Arg(a, 1), rest)
        }),
        .object(r.Function("makeSuppressed", 2) { _, a, _ in
            let proto = r.Intrinsics["SuppressedErrorPrototype"] ?? r.ErrorPrototype
            let e = object.MakeError(proto, str.JSString.From("An error was suppressed during disposal."))
            e.DefineData(object.Key("error"), object.Arg(a, 0), writable: true, enumerable: false, configurable: true)
            e.DefineData(object.Key("suppressed"), object.Arg(a, 1), writable: true, enumerable: false, configurable: true)
            return .object(e)
        }),
        .object(r.Function("defineMethodAlias", 4) { _, a, _ in
            // proto[sym] = proto[name], and proto[@@toStringTag] = tag.
            guard case .object(let proto) = object.Arg(a, 0), case .string(let name) = object.Arg(a, 1), case .symbol(let sym) = object.Arg(a, 2) else { return .undefined }
            let m = try proto.Get(value.PropertyKey.FromString(name), .object(proto))
            proto.DefineData(.symbol(sym), m, writable: true, enumerable: false, configurable: true)
            proto.DefineData(.symbol(value.SymToStringTag), object.Arg(a, 3), writable: false, enumerable: false, configurable: true)
            return .undefined
        }),
    ]
    guard let select = try? r.SelfHosted(disposeSource, helpers) else { return }
    func pick(_ i: int) -> object.JSObject? {
        if case .object(let o) = (try? object.Call(.object(select), .undefined, [.number(float64(i))])) ?? .undefined { return o }
        return nil
    }
    if let ds = pick(0) { r.DefineGlobal("DisposableStack", .object(ds)) }
    if let ads = pick(1) { r.DefineGlobal("AsyncDisposableStack", .object(ads)) }
    if let d = pick(2) {
        r.IteratorPrototype.DefineData(.symbol(value.SymDispose), .object(d), writable: true, enumerable: false, configurable: true)
    }
    if let ad = pick(3) {
        r.AsyncIteratorPrototype.DefineData(.symbol(value.SymAsyncDispose), .object(ad), writable: true, enumerable: false, configurable: true)
    }
}
