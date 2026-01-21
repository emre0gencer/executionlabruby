#!/usr/bin/env node

const fs = require("fs");

const input = fs.readFileSync(0, "utf8");
const payload = JSON.parse(input || "{}");
const program = payload.program;
const recordTraceEnabled = payload.record_trace === true;

class C0Value {
  constructor(kind, value) {
    this.kind = kind;
    this.value = value;
  }

  static int(value) {
    return new C0Value("int", value);
  }

  static ptr(value) {
    return new C0Value("ptr", value);
  }
}

class Pointer {
  constructor(block, offset = 0) {
    this.block = block;
    this.offset = offset;
  }
}

class TaggedPointer {
  constructor(ptr, tag) {
    this.ptr = ptr;
    this.tag = tag;
  }
}

class FunPtr {
  constructor(index, native) {
    this.index = index;
    this.native = native;
  }
}

class MemoryBlock {
  constructor(size) {
    this.size = size;
    this.bytes = new Array(size).fill(0);
    this.ptrSlots = new Map();
  }

  readInt32(offset) {
    const b0 = this.bytes[offset] ?? 0;
    const b1 = this.bytes[offset + 1] ?? 0;
    const b2 = this.bytes[offset + 2] ?? 0;
    const b3 = this.bytes[offset + 3] ?? 0;
    const value = (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)) >>> 0;
    return toInt32(value);
  }

  writeInt32(offset, value) {
    const v = value >>> 0;
    this.bytes[offset] = v & 0xff;
    this.bytes[offset + 1] = (v >> 8) & 0xff;
    this.bytes[offset + 2] = (v >> 16) & 0xff;
    this.bytes[offset + 3] = (v >> 24) & 0xff;
  }

  readByte(offset) {
    return this.bytes[offset] ?? 0;
  }

  writeByte(offset, value) {
    this.bytes[offset] = value & 0xff;
  }

  readPtr(offset) {
    return this.ptrSlots.get(offset) ?? null;
  }

  writePtr(offset, value) {
    this.ptrSlots.set(offset, value);
  }

  toString(offset = 0) {
    const bytes = [];
    let idx = offset;
    while (idx < this.bytes.length) {
      const b = this.bytes[idx];
      if (b === 0 || b === undefined) break;
      bytes.push(b);
      idx += 1;
    }
    return Buffer.from(bytes).toString("utf8");
  }
}

class ArrayObject {
  constructor(count, eltSize) {
    this.count = count;
    this.eltSize = eltSize;
    this.elems = new MemoryBlock(count * eltSize);
  }
}

function toInt32(value) {
  const v = value & 0xffffffff;
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

function sign8(value) {
  const v = value & 0xff;
  return v >= 0x80 ? v - 0x100 : v;
}

function sign16(value) {
  const v = value & 0xffff;
  return v >= 0x8000 ? v - 0x10000 : v;
}

function val2int(value) {
  if (value.kind !== "int") throw new Error("Invalid cast from pointer to integer");
  return value.value;
}

function val2ptr(value) {
  if (value.kind !== "ptr") throw new Error("Invalid cast from integer to pointer");
  return value.value;
}

function taggedPointer(ptr) {
  return ptr instanceof TaggedPointer;
}

function ptrType(ptr) {
  if (ptr instanceof FunPtr) return "funptr";
  if (ptr instanceof TaggedPointer) return "tagged";
  return "raw";
}

function valEqual(v1, v2) {
  if (v1.kind !== v2.kind) throw new Error("val_equal: invalid comparison of an int and a pointer");
  if (v1.kind === "int") return val2int(v1) === val2int(v2);

  const p1 = v1.value;
  const p2 = v2.value;
  if ((p1 === null) !== (p2 === null)) return false;
  if (p1 === null && p2 === null) return true;

  if (taggedPointer(p1) && taggedPointer(p2)) {
    return p1.ptr === p2.ptr;
  }

  if (!taggedPointer(p1) && !taggedPointer(p2)) {
    if (ptrType(p1) !== ptrType(p2)) {
      throw new Error("val_equal: invalid comparison between a function pointer and a regular pointer");
    }
    return p1 === p2;
  }

  throw new Error("val_equal: invalid comparison of a tagged pointer and an untagged pointer");
}

function normalizeProgram(program) {
  if (Array.isArray(program)) {
    return {
      functions: [
        {
          name: "main",
          num_args: 0,
          num_vars: 0,
          code: program.map((ins) => ({
            pc: ins.pc ?? ins["pc"],
            opcode: ins.opcode ?? ins["opcode"],
            operand: ins.operand ?? ins["operand"],
          })),
        },
      ],
      int_pool: [],
      string_pool: [],
      native_pool: [],
    };
  }

  const functions = (program.functions || program["functions"] || []).map((fn) => {
    const rawCode = fn.code ?? fn["code"];
    const code = (rawCode ?? []).map((ins) => ({
      pc: ins.pc ?? ins["pc"],
      opcode: ins.opcode ?? ins["opcode"],
      operand: ins.operand ?? ins["operand"],
    }));

    return {
      name: fn.name ?? fn["name"],
      num_args: fn.num_args ?? fn["num_args"],
      num_vars: fn.num_vars ?? fn["num_vars"],
      code,
    };
  });

  const stringPool = (program.string_pool || program["string_pool"] || []).map((str) => {
    const block = new MemoryBlock(str.length + 1);
    for (let i = 0; i < str.length; i += 1) {
      block.writeByte(i, str.charCodeAt(i));
    }
    block.writeByte(str.length, 0);
    return new Pointer(block, 0);
  });

  return {
    functions,
    int_pool: program.int_pool || program["int_pool"] || [],
    string_pool: stringPool,
    native_pool: program.native_pool || program["native_pool"] || [],
  };
}

function ptrToString(ptr) {
  if (ptr === null) return "";
  if (typeof ptr === "string") return ptr;
  if (ptr instanceof Pointer) return ptr.block.toString(ptr.offset);
  return String(ptr);
}

function buildInstructionMap(code) {
  const map = new Map();
  code.forEach((ins) => map.set(ins.pc, ins));
  return map;
}

const normalized = normalizeProgram(program || []);
const functions = normalized.functions;
const intPool = normalized.int_pool;
const stringPool = normalized.string_pool;
const nativePool = normalized.native_pool;

let stack = [];
let locals = [];
let callStack = [];
let code = [];
let pc = 0;
let status = "running";
let instructionCount = 0;
let maxStackDepth = 0;
let trace = [];
let result = null;

const main = functions[0];
code = main.code;
locals = new Array(main.num_args + main.num_vars).fill(C0Value.int(0));
let codeMap = buildInstructionMap(code);

function push(value) {
  stack.push(value);
  if (stack.length > maxStackDepth) maxStackDepth = stack.length;
}

function pop() {
  if (stack.length === 0) throw new Error("stack underflow");
  return stack.pop();
}

function recordTrace(opcode, operand) {
  if (!recordTraceEnabled) return;
  trace.push({
    pc,
    opcode,
    operand,
    stack: stack.map((v) => (v.kind === "int" ? { kind: "int", value: v.value } : { kind: "ptr", value: "ptr" })),
    locals: locals.map((v) => (v.kind === "int" ? { kind: "int", value: v.value } : { kind: "ptr", value: "ptr" })),
  });
}

function fetchInstruction(currentPc) {
  const ins = codeMap.get(currentPc);
  if (!ins) throw new Error(`no instruction at pc ${currentPc}`);
  return ins;
}

const start = process.hrtime.bigint();

while (status === "running") {
  const ins = fetchInstruction(pc);
  const opcode = ins.opcode;
  const operand = ins.operand;

  recordTrace(opcode, operand);
  instructionCount += 1;

  switch (opcode) {
    case "POP":
      pc += 1;
      pop();
      break;
    case "DUP": {
      pc += 1;
      const v = pop();
      push(v);
      push(v);
      break;
    }
    case "SWAP": {
      pc += 1;
      const v2 = pop();
      const v1 = pop();
      push(v2);
      push(v1);
      break;
    }
    case "RETURN": {
      const retv = pop();
      if (callStack.length === 0) {
        status = "completed";
        result = { return_value: val2int(retv), output: [] };
      } else {
        const frame = callStack.pop();
        stack = frame.stack;
        code = frame.code;
        pc = frame.pc;
        locals = frame.locals;
        codeMap = buildInstructionMap(code);
        push(retv);
      }
      break;
    }
    case "IADD": {
      pc += 1;
      const y = val2int(pop());
      const x = val2int(pop());
      push(C0Value.int(toInt32(x + y)));
      break;
    }
    case "ISUB": {
      pc += 1;
      const y = val2int(pop());
      const x = val2int(pop());
      push(C0Value.int(toInt32(x - y)));
      break;
    }
    case "IMUL": {
      pc += 1;
      const y = val2int(pop());
      const x = val2int(pop());
      push(C0Value.int(toInt32(x * y)));
      break;
    }
    case "IDIV": {
      pc += 1;
      const y = val2int(pop());
      const x = val2int(pop());
      if (y === 0) throw new Error("Division by zero");
      push(C0Value.int(toInt32(Math.trunc(x / y))));
      break;
    }
    case "IREM": {
      pc += 1;
      const y = val2int(pop());
      const x = val2int(pop());
      if (y === 0) throw new Error("Remainder by zero");
      const q = Math.trunc(x / y);
      push(C0Value.int(toInt32(x - q * y)));
      break;
    }
    case "IAND": {
      pc += 1;
      const y = val2int(pop());
      const x = val2int(pop());
      push(C0Value.int(toInt32(x & y)));
      break;
    }
    case "IOR": {
      pc += 1;
      const y = val2int(pop());
      const x = val2int(pop());
      push(C0Value.int(toInt32(x | y)));
      break;
    }
    case "IXOR": {
      pc += 1;
      const y = val2int(pop());
      const x = val2int(pop());
      push(C0Value.int(toInt32(x ^ y)));
      break;
    }
    case "ISHR": {
      pc += 1;
      const y = val2int(pop());
      const x = val2int(pop());
      if (y < 0 || y >= 32) throw new Error("Shift out of range");
      push(C0Value.int(toInt32(x >> y)));
      break;
    }
    case "ISHL": {
      pc += 1;
      const y = val2int(pop());
      const x = val2int(pop());
      if (y < 0 || y >= 32) throw new Error("Shift out of range");
      push(C0Value.int(toInt32(x << y)));
      break;
    }
    case "BIPUSH": {
      push(C0Value.int(sign8(operand)));
      pc += 2;
      break;
    }
    case "ILDC": {
      const value = intPool[operand];
      push(C0Value.int(toInt32(value)));
      pc += 3;
      break;
    }
    case "ALDC": {
      const ptr = stringPool[operand];
      push(C0Value.ptr(ptr));
      pc += 3;
      break;
    }
    case "ACONST_NULL": {
      push(C0Value.ptr(null));
      pc += 1;
      break;
    }
    case "VLOAD": {
      push(locals[operand]);
      pc += 2;
      break;
    }
    case "VSTORE": {
      locals[operand] = pop();
      pc += 2;
      break;
    }
    case "ATHROW": {
      const msgPtr = val2ptr(pop());
      throw new Error(ptrToString(msgPtr));
    }
    case "ASSERT": {
      const msgPtr = val2ptr(pop());
      const value = val2int(pop());
      if (value === 0) throw new Error(ptrToString(msgPtr));
      pc += 1;
      break;
    }
    case "NOP":
      pc += 1;
      break;
    case "IF_CMPEQ": {
      const v2 = pop();
      const v1 = pop();
      const offset = sign16(operand);
      if (valEqual(v1, v2)) {
        pc = pc + offset;
      } else {
        pc += 3;
      }
      break;
    }
    case "IF_CMPNE": {
      const v2 = pop();
      const v1 = pop();
      const offset = sign16(operand);
      if (!valEqual(v1, v2)) {
        pc = pc + offset;
      } else {
        pc += 3;
      }
      break;
    }
    case "IF_ICMPLT": {
      const y = val2int(pop());
      const x = val2int(pop());
      const offset = sign16(operand);
      if (x < y) pc = pc + offset;
      else pc += 3;
      break;
    }
    case "IF_ICMPGE": {
      const y = val2int(pop());
      const x = val2int(pop());
      const offset = sign16(operand);
      if (x >= y) pc = pc + offset;
      else pc += 3;
      break;
    }
    case "IF_ICMPGT": {
      const y = val2int(pop());
      const x = val2int(pop());
      const offset = sign16(operand);
      if (x > y) pc = pc + offset;
      else pc += 3;
      break;
    }
    case "IF_ICMPLE": {
      const y = val2int(pop());
      const x = val2int(pop());
      const offset = sign16(operand);
      if (x <= y) pc = pc + offset;
      else pc += 3;
      break;
    }
    case "GOTO": {
      const offset = sign16(operand);
      pc = pc + offset;
      break;
    }
    case "INVOKESTATIC": {
      const func = functions[operand];
      const returnPc = pc + 3;
      const numArgs = func.num_args;
      const numVars = func.num_vars;
      const localsNew = new Array(numArgs + numVars).fill(C0Value.int(0));
      for (let i = numArgs - 1; i >= 0; i -= 1) {
        localsNew[i] = pop();
      }
      callStack.push({ stack, code, pc: returnPc, locals });
      stack = [];
      locals = localsNew;
      code = func.code;
      pc = 0;
      codeMap = buildInstructionMap(code);
      break;
    }
    case "INVOKENATIVE": {
      const native = nativePool[operand];
      if (!native) throw new Error("native function not registered");
      throw new Error("native functions not supported in node runtime");
    }
    case "NEW": {
      const ptr = new Pointer(new MemoryBlock(operand), 0);
      push(C0Value.ptr(ptr));
      pc += 2;
      break;
    }
    case "IMLOAD": {
      pc += 1;
      const ptr = val2ptr(pop());
      if (ptr === null) throw new Error("imload on NULL");
      push(C0Value.int(ptr.block.readInt32(ptr.offset)));
      break;
    }
    case "IMSTORE": {
      pc += 1;
      const value = val2int(pop());
      const ptr = val2ptr(pop());
      if (ptr === null) throw new Error("imstore on NULL");
      ptr.block.writeInt32(ptr.offset, value);
      break;
    }
    case "AMLOAD": {
      pc += 1;
      const ptr = val2ptr(pop());
      if (ptr === null) throw new Error("amload on NULL");
      push(C0Value.ptr(ptr.block.readPtr(ptr.offset)));
      break;
    }
    case "AMSTORE": {
      pc += 1;
      const value = val2ptr(pop());
      const ptr = val2ptr(pop());
      if (ptr === null) throw new Error("amstore on NULL");
      ptr.block.writePtr(ptr.offset, value);
      break;
    }
    case "CMLOAD": {
      pc += 1;
      const ptr = val2ptr(pop());
      if (ptr === null) throw new Error("cmload on NULL");
      push(C0Value.int(toInt32(ptr.block.readByte(ptr.offset))));
      break;
    }
    case "CMSTORE": {
      pc += 1;
      const value = val2int(pop());
      const ptr = val2ptr(pop());
      if (ptr === null) throw new Error("cmstore on NULL");
      ptr.block.writeByte(ptr.offset, value & 0x7f);
      break;
    }
    case "AADDF": {
      const ptr = val2ptr(pop());
      if (ptr === null) throw new Error("aaddf on NULL");
      pc += 2;
      push(C0Value.ptr(new Pointer(ptr.block, ptr.offset + operand)));
      break;
    }
    case "NEWARRAY": {
      const capacity = val2int(pop());
      if (capacity < 0) throw new Error("invalid size");
      pc += 2;
      if (capacity === 0) {
        push(C0Value.ptr(null));
      } else {
        push(C0Value.ptr(new ArrayObject(capacity, operand)));
      }
      break;
    }
    case "ARRAYLENGTH": {
      pc += 1;
      const ptr = val2ptr(pop());
      const length = ptr === null ? 0 : ptr.count;
      push(C0Value.int(toInt32(length)));
      break;
    }
    case "AADDS": {
      pc += 1;
      const index = val2int(pop());
      const arrayPtr = val2ptr(pop());
      if (arrayPtr === null) throw new Error("aadds on NULL array");
      const len = arrayPtr.count;
      if (index < 0 || index >= len) throw new Error("array index out of bounds");
      const offset = index * arrayPtr.eltSize;
      push(C0Value.ptr(new Pointer(arrayPtr.elems, offset)));
      break;
    }
    case "CHECKTAG":
    case "HASTAG":
    case "ADDTAG":
    case "ADDROF_STATIC":
    case "ADDROF_NATIVE":
    case "INVOKEDYNAMIC":
      throw new Error(`unsupported opcode ${opcode}`);
    default:
      throw new Error(`invalid opcode ${opcode}`);
  }
}

const end = process.hrtime.bigint();
const durationMs = Number(end - start) / 1_000_000;

const output = {
  result,
  metrics: {
    execution_time_ms: Math.round(durationMs * 1000) / 1000,
    instruction_count: instructionCount,
    max_stack_depth: maxStackDepth,
    runtime: "node",
  },
  trace,
};

process.stdout.write(JSON.stringify(output));
