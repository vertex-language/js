package codegen

import (
    "js/ast"
    "js/bytecode"
    "js/str"
)

extension Builder {
    /// classDef compiles ClassDefinitionEvaluation (§15.7.14), leaving the
    /// constructor in the accumulator.
    func classDef(_ c: ast.ClassNode, nameHint: string?) throws {
        let m = mark()
        defer { release(m) }
        at(c.At)
        let cs = c.Scope!
        let outer = scope
        enterScope(cs)
        // Private names: fresh for each evaluation of the class.
        for b in cs.Order where b.Name.hasPrefix("#") {
            emit(.newPrivateName, strConst(b.Name))
            storeBinding(b, name: b.Name, initialize: true)
        }
        var superReg: int32 = -1
        if let sup = c.SuperClass {
            superReg = try exprToReg(sup)
        }
        var name = c.Name
        if name.isEmpty, let h = nameHint { name = h }
        let ctorTemplate = try constructorTemplate(c, name: name)
        let proto = temp()
        emit(.createClass, constIndex(.function(ctorTemplate)), superReg, proto)
        let F = temp()
        emit(.star, F)

        // Static elements run after all are defined; keep their keys.
        var statics: [(ast.ClassElement, int32, int32)] = []
        for el in c.Elements {
            let home = el.IsStatic ? F : proto
            switch el.Kind {
            case .method, .getter, .setter:
                if case .privateName = el.Key {
                    let n = temp()
                    loadBinding(el.PrivateBinding!, name: el.PrivateBinding!.Name)
                    emit(.star, n)
                    try compileClosure(el.Value!, nameHint: nil)
                    // A private method's home object is the class's own.
                    let fn = temp()
                    emit(.star, fn)
                    emit(.ldar, fn)
                    let kind: int32 = el.Kind == .getter ? 1 : (el.Kind == .setter ? 2 : 0)
                    emit(.setHomeObject, home)
                    if el.IsStatic {
                        emit(.addStaticPrivateMethod, F, n, kind)
                    } else {
                        emit(.addPrivateMethod, F, n, kind)
                    }
                } else {
                    let k = try propertyKeyToReg(el.Key)
                    try compileClosure(el.Value!, nameHint: keyHint(el.Key))
                    switch el.Kind {
                    case .getter: emit(.defineGetter, home, k, 0)
                    case .setter: emit(.defineSetter, home, k, 0)
                    default: emit(.defineMethod, home, k, 0)
                    }
                }
            case .field:
                var k: int32
                if case .privateName = el.Key {
                    k = temp()
                    loadBinding(el.PrivateBinding!, name: el.PrivateBinding!.Name)
                    emit(.star, k)
                } else {
                    k = try propertyKeyToReg(el.Key)
                }
                var initReg: int32 = -1
                if let f = el.Value {
                    try compileClosure(f, nameHint: nil)
                    emit(.setHomeObject, home)
                    initReg = temp()
                    emit(.star, initReg)
                }
                if el.IsStatic {
                    statics.append((el, k, initReg))
                } else {
                    emit(.addField, F, k, initReg)
                }
            case .staticBlock:
                try compileClosure(el.Value!, nameHint: nil)
                emit(.setHomeObject, F)
                let fn = temp()
                emit(.star, fn)
                statics.append((el, fn, fn))
            }
        }
        // The class's inner name.
        if let nb = c.NameBinding {
            emit(.ldar, F)
            storeBinding(nb, name: c.Name, initialize: true)
        }
        // Static fields and blocks, in order.
        for (el, reg, initFn) in statics {
            if el.Kind == .staticBlock {
                let args = temps(1)
                emit(.ldar, F)
                emit(.star, args)
                emit(.callMethod, reg, args, 0)
                continue
            }
            if initFn >= 0 {
                let args = temps(1)
                emit(.ldar, F)
                emit(.star, args)
                emit(.callMethod, initFn, args, 0)
            } else {
                emit(.ldaUndefined)
            }
            if case .privateName = el.Key {
                emit(.definePrivate, F, reg)
            } else {
                emit(.defineKeyed, F, reg)
            }
        }
        exitScope(cs)
        scope = outer
        emit(.ldar, F)
    }

    /// constructorTemplate compiles the class's constructor, or makes the
    /// default one: empty for a base class, forwarding its arguments to
    /// super for a derived one.
    func constructorTemplate(_ c: ast.ClassNode, name: string) throws -> bytecode.FunctionTemplate {
        if let ctor = c.Constructor {
            let t = try compileFunction(ctor, nameHint: name)
            t.Name = str.JSString.From(name)
            t.Start = c.Start
            t.End = c.End
            return t
        }
        let derived = c.SuperClass != nil
        let t = bytecode.FunctionTemplate(name: str.JSString.From(name), kind: derived ? .derivedConstructor : .classConstructor)
        t.Strict = true
        t.Source = source
        t.Start = c.Start
        t.End = c.End
        t.Line = lineOf(c.At)
        t.NeedsFunctionEnv = derived
        t.IsDefaultDerivedConstructor = derived
        if derived {
            t.Code.append(bytecode.Instruction(.superCallForward))
        }
        t.Code.append(bytecode.Instruction(.ldaUndefined))
        t.Code.append(bytecode.Instruction(.returnOp))
        return t
    }
}
