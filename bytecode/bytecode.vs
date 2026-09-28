package bytecode

/// Opcode defines the register-based bytecode instruction set with accumulator.
public enum Opcode: Equatable {
    // Accumulator constants
    case ldaUndefined
    case ldaNull
    case ldaTrue
    case ldaFalse
    case ldaZero
    case ldaInt32
    case ldaConstant

    // Register moves
    case ldar             // Acc = Reg[r0]
    case star             // Reg[r0] = Acc
    case mov              // Reg[r1] = Reg[r0]

    // Properties and Globals
    case ldaGlobal        // Acc = Global[const[imm]]
    case staGlobal        // Global[const[imm]] = Acc
    case ldaNamedProperty // Acc = Reg[r0].[const[imm]]
    case staNamedProperty // Reg[r0].[const[imm]] = Acc
    case ldaKeyedProperty // Acc = Reg[r0][Acc]
    case staKeyedProperty // Reg[r0][Reg[r1]] = Acc
    case ldaContextSlot   // Acc = Context[r0][r1]
    case staContextSlot   // Context[r0][r1] = Acc

    // Arithmetic and Bitwise (Acc = Reg[r0] <op> Acc)
    case add
    case sub
    case mul
    case div
    case mod
    case exp
    case bitAnd
    case bitOr
    case bitXor
    case shiftLeft
    case shiftRight
    case shiftRightLogical

    // Unary
    case negate
    case bitwiseNot
    case toBooleanLogicalNot
    case typeOf

    // Comparisons (Acc = Reg[r0] <op> Acc)
    case testEqual
    case testStrictEqual
    case testNotEqual
    case testStrictNotEqual
    case testLessThan
    case testGreaterThan
    case testLessThanOrEqual
    case testGreaterThanOrEqual
    case testIn
    case testInstanceOf

    // Jumps
    case jump             // PC += offset
    case jumpIfTrue       // if (ToBoolean(Acc)) PC += offset
    case jumpIfFalse      // if (!ToBoolean(Acc)) PC += offset
    case jumpIfNull       // if (Acc == null) PC += offset
    case jumpIfUndefined  // if (Acc == undefined) PC += offset

    // Calls and Returns
    case call             // Acc = Call(Reg[r0], receiver: Reg[r1], args: Reg[r2...r2+imm])
    case callProperty     // Acc = CallProp(Reg[r0], name: const[imm], args: Reg[r1...r1+r2])
    case construct        // Acc = Construct(Reg[r0], args: Reg[r1...r1+imm])
    case returnOp         // Return Acc
    case throwOp          // Throw Acc

    // Object and Array creation
    case createObjectLiteral
    case createArrayLiteral
    case createClosure
    case setProto
}

/// Instruction represents a single bytecode operation with register/immediate operands.
public struct Instruction: Equatable {
    public var Op: Opcode
    public var R0: int32
    public var R1: int32
    public var R2: int32
    public var Imm: int32
    public var Offset: int32
    public var FeedbackSlot: int32

    public init(op: Opcode, r0: int32 = 0, r1: int32 = 0, r2: int32 = 0, imm: int32 = 0, offset: int32 = 0, slot: int32 = -1) {
        self.Op = op
        self.R0 = r0
        self.R1 = r1
        self.R2 = r2
        self.Imm = imm
        self.Offset = offset
        self.FeedbackSlot = slot
    }
}

/// ConstantValue holds a primitive or nested function stored in the constant pool.
public enum ConstantValue {
    case stringVal(string)
    case numberVal(float64)
    case boolVal(bool)
    case fnVal(BytecodeFunction)
}

/// PositionEntry maps bytecode offsets to source line and column numbers.
public struct PositionEntry: Equatable {
    public var BytecodeOffset: int
    public var SourceOffset: int
    public var Line: int
    public var Column: int

    public init(bytecodeOffset: int, sourceOffset: int, line: int = 1, column: int = 1) {
        self.BytecodeOffset = bytecodeOffset
        self.SourceOffset = sourceOffset
        self.Line = line
        self.Column = column
    }
}

/// BytecodeFunction holds the compiled instructions, constants, and metadata for a function.
public final class BytecodeFunction {
    public var Name: string
    public var ParameterCount: int
    public var RegisterCount: int
    public var Instructions: [Instruction] = []
    public var Constants: [ConstantValue] = []
    public var PositionTable: [PositionEntry] = []
    public var FeedbackSlotCount: int = 0

    public init(name: string = "", parameterCount: int = 0, registerCount: int = 0) {
        self.Name = name
        self.ParameterCount = parameterCount
        self.RegisterCount = registerCount
    }

    /// AddConstant adds a constant value and returns its pool index.
    public func AddConstant(_ val: ConstantValue) -> int32 {
        Constants.append(val)
        return int32(Constants.count - 1)
    }

    /// Emit appends an instruction and returns its instruction index.
    public func Emit(_ instr: Instruction) -> int {
        Instructions.append(instr)
        return Instructions.count - 1
    }
}

/// Disassemble formats a BytecodeFunction into human-readable disassembly.
public func Disassemble(_ fn: BytecodeFunction) -> string {
    var out = "=== Bytecode: \(fn.Name.isEmpty ? "<anonymous>" : fn.Name) ===\n"
    out += "Parameters: \(fn.ParameterCount), Registers: \(fn.RegisterCount), Constants: \(fn.Constants.count)\n"
    for i in 0..<fn.Instructions.count {
        let instr = fn.Instructions[i]
        var numStr = "\(i)"
        while numStr.count < 4 { numStr = "0" + numStr }
        out += numStr + "  "
        switch instr.Op {
        case .ldaUndefined: out += "LdaUndefined\n"
        case .ldaNull: out += "LdaNull\n"
        case .ldaTrue: out += "LdaTrue\n"
        case .ldaFalse: out += "LdaFalse\n"
        case .ldaZero: out += "LdaZero\n"
        case .ldaInt32: out += "LdaInt32 [\(instr.Imm)]\n"
        case .ldaConstant: out += "LdaConstant [\(instr.Imm)]\n"
        case .ldar: out += "Ldar r\(instr.R0)\n"
        case .star: out += "Star r\(instr.R0)\n"
        case .mov: out += "Mov r\(instr.R0), r\(instr.R1)\n"
        case .ldaGlobal: out += "LdaGlobal [const \(instr.Imm)]\n"
        case .staGlobal: out += "StaGlobal [const \(instr.Imm)]\n"
        case .ldaNamedProperty: out += "LdaNamedProperty r\(instr.R0), [const \(instr.Imm)]\n"
        case .staNamedProperty: out += "StaNamedProperty r\(instr.R0), [const \(instr.Imm)]\n"
        case .ldaKeyedProperty: out += "LdaKeyedProperty r\(instr.R0)\n"
        case .staKeyedProperty: out += "StaKeyedProperty r\(instr.R0), r\(instr.R1)\n"
        case .ldaContextSlot: out += "LdaContextSlot [ctx \(instr.R0), slot \(instr.R1)]\n"
        case .staContextSlot: out += "StaContextSlot [ctx \(instr.R0), slot \(instr.R1)]\n"
        case .add: out += "Add r\(instr.R0)\n"
        case .sub: out += "Sub r\(instr.R0)\n"
        case .mul: out += "Mul r\(instr.R0)\n"
        case .div: out += "Div r\(instr.R0)\n"
        case .mod: out += "Mod r\(instr.R0)\n"
        case .exp: out += "Exp r\(instr.R0)\n"
        case .bitAnd: out += "BitAnd r\(instr.R0)\n"
        case .bitOr: out += "BitOr r\(instr.R0)\n"
        case .bitXor: out += "BitXor r\(instr.R0)\n"
        case .shiftLeft: out += "ShiftLeft r\(instr.R0)\n"
        case .shiftRight: out += "ShiftRight r\(instr.R0)\n"
        case .shiftRightLogical: out += "ShiftRightLogical r\(instr.R0)\n"
        case .negate: out += "Negate\n"
        case .bitwiseNot: out += "BitwiseNot\n"
        case .toBooleanLogicalNot: out += "ToBooleanLogicalNot\n"
        case .typeOf: out += "TypeOf\n"
        case .testEqual: out += "TestEqual r\(instr.R0)\n"
        case .testStrictEqual: out += "TestStrictEqual r\(instr.R0)\n"
        case .testNotEqual: out += "TestNotEqual r\(instr.R0)\n"
        case .testStrictNotEqual: out += "TestStrictNotEqual r\(instr.R0)\n"
        case .testLessThan: out += "TestLessThan r\(instr.R0)\n"
        case .testGreaterThan: out += "TestGreaterThan r\(instr.R0)\n"
        case .testLessThanOrEqual: out += "TestLessThanOrEqual r\(instr.R0)\n"
        case .testGreaterThanOrEqual: out += "TestGreaterThanOrEqual r\(instr.R0)\n"
        case .testIn: out += "TestIn r\(instr.R0)\n"
        case .testInstanceOf: out += "TestInstanceOf r\(instr.R0)\n"
        case .jump: out += "Jump -> \(i + Int(instr.Offset))\n"
        case .jumpIfTrue: out += "JumpIfTrue -> \(i + Int(instr.Offset))\n"
        case .jumpIfFalse: out += "JumpIfFalse -> \(i + Int(instr.Offset))\n"
        case .jumpIfNull: out += "JumpIfNull -> \(i + Int(instr.Offset))\n"
        case .jumpIfUndefined: out += "JumpIfUndefined -> \(i + Int(instr.Offset))\n"
        case .call: out += "Call r\(instr.R0), this: r\(instr.R1), args: \(instr.Imm)\n"
        case .callProperty: out += "CallProperty r\(instr.R0), [const \(instr.Imm)], args: \(instr.R2)\n"
        case .construct: out += "Construct r\(instr.R0), args: \(instr.Imm)\n"
        case .returnOp: out += "Return\n"
        case .throwOp: out += "Throw\n"
        case .createObjectLiteral: out += "CreateObjectLiteral\n"
        case .createArrayLiteral: out += "CreateArrayLiteral [count \(instr.Imm)]\n"
        case .createClosure: out += "CreateClosure [const \(instr.Imm)]\n"
        case .setProto: out += "SetProto r\(instr.R0)\n"
        }
    }
    return out
}
