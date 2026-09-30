package codegen

import (
    "js/ast"
    "js/bytecode"
)

extension Builder {
    /// bindPatternFromAcc binds the accumulator's value to a pattern: a
    /// declaration's (initialize) or an assignment's targets.
    func bindPatternFromAcc(_ p: ast.Pattern, initialize: bool) throws {
        switch p {
        case .identifier(let id):
            storeIdentifier(id, initialize: initialize)
        case .member:
            let m = mark()
            let v = temp()
            emit(.star, v)
            let ref = try reference(p)
            emit(.ldar, v)
            storeReference(ref)
            release(m)
        case .object(let o):
            let m = mark()
            let v = temp()
            emit(.star, v)
            try objectPattern(o, v, initialize: initialize)
            release(m)
        case .array(let a):
            let m = mark()
            let v = temp()
            emit(.star, v)
            try arrayPattern(a, v, initialize: initialize)
            release(m)
        }
    }

    /// bindElement binds acc, applying a default for undefined.
    func bindElement(_ el: ast.PatternElement, initialize: bool) throws {
        if let d = el.Default {
            let skip = newLabel()
            jump(.jumpIfNotUndefined, skip)
            try exprNamed(d, patternName(el.Target))
            bind(skip)
        }
        try bindPatternFromAcc(el.Target, initialize: initialize)
    }

    func objectPattern(_ o: ast.ObjectPattern, _ v: int32, initialize: bool) throws {
        emit(.ldar, v)
        emit(.requireObjectCoercible)
        // With a rest, the keys taken are excluded from it.
        var excluded: int32 = -1
        if o.Rest != nil {
            emit(.createArray)
            excluded = temp()
            emit(.star, excluded)
        }
        for prop in o.Properties {
            let m = mark()
            switch prop.Key {
            case .named(let n):
                emit(.getNamed, v, keyConst(n))
                if excluded >= 0 {
                    let tmp = temp()
                    emit(.star, tmp)
                    emit(.ldaConst, strConst(n))
                    emit(.arrayPush, excluded)
                    emit(.ldar, tmp)
                }
            default:
                let k = try propertyKeyToReg(prop.Key)
                if excluded >= 0 {
                    emit(.ldar, k)
                    emit(.arrayPush, excluded)
                }
                emit(.ldar, k)
                emit(.getKeyed, v)
            }
            try bindElement(prop.Value, initialize: initialize)
            release(m)
        }
        if let rest = o.Rest {
            emit(.createObject)
            let r = temp()
            emit(.star, r)
            emit(.ldar, v)
            emit(.copyDataProperties, r, excluded)
            emit(.ldar, r)
            try bindPatternFromAcc(rest, initialize: initialize)
        }
    }

    func arrayPattern(_ a: ast.ArrayPattern, _ v: int32, initialize: bool) throws {
        emit(.ldar, v)
        let iter = temps(3)
        emit(.getIterator, iter)
        let kindReg = temp()
        let valueReg = temp()
        let depth = contextDepth
        let start = t.Code.count
        let ctl = Control(kind: .iterator)
        ctl.iterReg = iter
        for el in a.Elements {
            let m = mark()
            // The next value, or undefined once the iterator is done.
            let got = newLabel()
            let exhausted = newLabel()
            emit(.ldaUndefined)
            let slot = temp()
            emit(.star, slot)
            emit(.ldar, iter + 2)
            jump(.jumpIfTrue, exhausted)
            jumpB(.iteratorStep, iter, exhausted)
            emit(.star, slot)
            bind(got)
            bind(exhausted)
            if let e = el {
                emit(.ldar, slot)
                try bindElement(e, initialize: initialize)
            }
            release(m)
        }
        if let rest = a.Rest {
            emit(.iteratorToArray, iter)
            try bindPatternFromAcc(rest, initialize: initialize)
        }
        let stop = t.Code.count
        // Done with it: close the iterator if it isn't exhausted.
        let closed = newLabel()
        emit(.ldar, iter + 2)
        jump(.jumpIfTrue, closed)
        emit(.iteratorClose, iter)
        jump(.jump, closed)
        // A throw while binding closes it too, keeping the exception.
        let throwPad = t.Code.count
        emit(.star, valueReg)
        emit(.ldaSmi, 1)
        emit(.star, kindReg)
        let cleanup = t.Code.count
        let notThrow = newLabel()
        emit(.ldaSmi, 1)
        emit(.testStrictEq, kindReg)
        jump(.jumpIfFalse, notThrow)
        let skipClose = newLabel()
        emit(.ldar, iter + 2)
        jump(.jumpIfTrue, skipClose)
        emit(.iteratorCloseThrow, iter)
        bind(skipClose)
        emit(.ldar, valueReg)
        emit(.throwOp)
        bind(notThrow)
        emit(.ldar, iter + 2)
        let skip2 = newLabel()
        jump(.jumpIfTrue, skip2)
        emit(.iteratorClose, iter)
        bind(skip2)
        unwind(to: -1, .ret(valueReg))
        t.Handlers.append(bytecode.Handler(start: start, end: stop, target: throwPad, isFinally: true, kindReg: int(kindReg), valueReg: int(valueReg), finallyStart: cleanup, contextDepth: depth))
        bind(closed)
        _ = ctl
    }
}
