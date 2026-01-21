#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

// ---------------- JSON parser (minimal, tailored) ----------------

typedef enum {
  JSON_NULL,
  JSON_BOOL,
  JSON_NUMBER,
  JSON_STRING,
  JSON_ARRAY,
  JSON_OBJECT
} JsonType;

typedef struct JsonValue JsonValue;

typedef struct {
  char *key;
  JsonValue *value;
} JsonPair;

typedef struct {
  JsonPair *pairs;
  size_t count;
} JsonObject;

typedef struct {
  JsonValue **items;
  size_t count;
} JsonArray;

struct JsonValue {
  JsonType type;
  union {
    double number;
    int boolean;
    char *string;
    JsonObject object;
    JsonArray array;
  } as;
};

static const char *skip_ws(const char *p) {
  while (*p == ' ' || *p == '\n' || *p == '\r' || *p == '\t') p++;
  return p;
}

static JsonValue *parse_value(const char **p);

static char *parse_string(const char **p) {
  const char *s = *p;
  if (*s != '"') return NULL;
  s++;
  const char *start = s;
  size_t len = 0;
  while (*s && *s != '"') {
    if (*s == '\\' && s[1]) {
      s += 2;
      len += 1;
      continue;
    }
    s++;
    len++;
  }
  if (*s != '"') return NULL;
  char *out = (char *)malloc(len + 1);
  if (!out) return NULL;
  size_t i = 0;
  s = start;
  while (*s && *s != '"') {
    if (*s == '\\' && s[1]) {
      s++;
      char c = *s;
      if (c == 'n') out[i++] = '\n';
      else if (c == 'r') out[i++] = '\r';
      else if (c == 't') out[i++] = '\t';
      else out[i++] = c;
      s++;
      continue;
    }
    out[i++] = *s++;
  }
  out[i] = '\0';
  s++; // closing quote
  *p = s;
  return out;
}

static JsonValue *new_value(JsonType type) {
  JsonValue *v = (JsonValue *)calloc(1, sizeof(JsonValue));
  if (!v) return NULL;
  v->type = type;
  return v;
}

static JsonValue *parse_number(const char **p) {
  const char *s = *p;
  char *end = NULL;
  double val = strtod(s, &end);
  if (s == end) return NULL;
  JsonValue *v = new_value(JSON_NUMBER);
  v->as.number = val;
  *p = end;
  return v;
}

static JsonValue *parse_array(const char **p) {
  const char *s = *p;
  if (*s != '[') return NULL;
  s++;
  JsonValue *v = new_value(JSON_ARRAY);
  v->as.array.items = NULL;
  v->as.array.count = 0;

  s = skip_ws(s);
  if (*s == ']') {
    s++;
    *p = s;
    return v;
  }

  while (*s) {
    s = skip_ws(s);
    JsonValue *item = parse_value(&s);
    if (!item) return NULL;

    v->as.array.items = (JsonValue **)realloc(
      v->as.array.items, (v->as.array.count + 1) * sizeof(JsonValue *)
    );
    v->as.array.items[v->as.array.count++] = item;

    s = skip_ws(s);
    if (*s == ',') {
      s++;
      continue;
    }
    if (*s == ']') {
      s++;
      break;
    }
    return NULL;
  }

  *p = s;
  return v;
}

static JsonValue *parse_object(const char **p) {
  const char *s = *p;
  if (*s != '{') return NULL;
  s++;
  JsonValue *v = new_value(JSON_OBJECT);
  v->as.object.pairs = NULL;
  v->as.object.count = 0;

  s = skip_ws(s);
  if (*s == '}') {
    s++;
    *p = s;
    return v;
  }

  while (*s) {
    s = skip_ws(s);
    char *key = parse_string(&s);
    if (!key) return NULL;
    s = skip_ws(s);
    if (*s != ':') return NULL;
    s++;
    s = skip_ws(s);
    JsonValue *val = parse_value(&s);
    if (!val) return NULL;

    v->as.object.pairs = (JsonPair *)realloc(
      v->as.object.pairs, (v->as.object.count + 1) * sizeof(JsonPair)
    );
    v->as.object.pairs[v->as.object.count].key = key;
    v->as.object.pairs[v->as.object.count].value = val;
    v->as.object.count++;

    s = skip_ws(s);
    if (*s == ',') {
      s++;
      continue;
    }
    if (*s == '}') {
      s++;
      break;
    }
    return NULL;
  }

  *p = s;
  return v;
}

static JsonValue *parse_value(const char **p) {
  const char *s = skip_ws(*p);
  if (*s == '"') {
    char *str = parse_string(&s);
    if (!str) return NULL;
    JsonValue *v = new_value(JSON_STRING);
    v->as.string = str;
    *p = s;
    return v;
  }
  if (*s == '{') {
    JsonValue *v = parse_object(&s);
    *p = s;
    return v;
  }
  if (*s == '[') {
    JsonValue *v = parse_array(&s);
    *p = s;
    return v;
  }
  if (!strncmp(s, "true", 4)) {
    JsonValue *v = new_value(JSON_BOOL);
    v->as.boolean = 1;
    *p = s + 4;
    return v;
  }
  if (!strncmp(s, "false", 5)) {
    JsonValue *v = new_value(JSON_BOOL);
    v->as.boolean = 0;
    *p = s + 5;
    return v;
  }
  if (!strncmp(s, "null", 4)) {
    JsonValue *v = new_value(JSON_NULL);
    *p = s + 4;
    return v;
  }
  JsonValue *num = parse_number(&s);
  if (num) {
    *p = s;
    return num;
  }
  return NULL;
}

static JsonValue *json_parse(const char *input) {
  const char *p = input;
  JsonValue *v = parse_value(&p);
  return v;
}

static JsonValue *json_object_get(JsonValue *obj, const char *key) {
  if (!obj || obj->type != JSON_OBJECT) return NULL;
  for (size_t i = 0; i < obj->as.object.count; i++) {
    if (strcmp(obj->as.object.pairs[i].key, key) == 0) {
      return obj->as.object.pairs[i].value;
    }
  }
  return NULL;
}

// ---------------- VM implementation ----------------

typedef enum { VAL_INT, VAL_PTR } ValKind;

typedef struct Pointer Pointer;

typedef struct {
  ValKind kind;
  union {
    int32_t i;
    Pointer *p;
  } as;
} C0Value;

typedef struct {
  uint8_t *bytes;
  size_t size;
  Pointer **ptr_slots;
  size_t ptr_slots_count;
} MemoryBlock;

typedef enum { PTR_BLOCK, PTR_ARRAY } PtrType;

struct Pointer {
  PtrType type;
  void *obj;
  size_t offset;
};

typedef struct {
  int32_t count;
  int32_t elt_size;
  MemoryBlock *elems;
} ArrayObject;

typedef struct {
  int pc;
  const char *opcode;
  int has_operand;
  int32_t operand;
} Instruction;

typedef struct {
  Instruction *code;
  size_t count;
  int *pc_index;
  int max_pc;
  int num_args;
  int num_vars;
} Function;

typedef struct {
  Function *functions;
  size_t function_count;
  int32_t *int_pool;
  size_t int_count;
  Pointer **string_pool;
  size_t string_count;
} Program;

typedef struct {
  C0Value *data;
  size_t count;
  size_t capacity;
} Stack;

typedef struct {
  Stack stack;
  Function *func;
  int pc;
  C0Value *locals;
  int locals_count;
} Frame;

typedef struct {
  Frame *data;
  size_t count;
  size_t capacity;
} CallStack;

static void stack_init(Stack *s) {
  s->data = NULL;
  s->count = 0;
  s->capacity = 0;
}

static void stack_push(Stack *s, C0Value v) {
  if (s->count == s->capacity) {
    s->capacity = s->capacity ? s->capacity * 2 : 16;
    s->data = (C0Value *)realloc(s->data, s->capacity * sizeof(C0Value));
  }
  s->data[s->count++] = v;
}

static C0Value stack_pop(Stack *s) {
  if (s->count == 0) {
    fprintf(stderr, "stack underflow\n");
    exit(1);
  }
  return s->data[--s->count];
}

static void callstack_init(CallStack *cs) {
  cs->data = NULL;
  cs->count = 0;
  cs->capacity = 0;
}

static void callstack_push(CallStack *cs, Frame f) {
  if (cs->count == cs->capacity) {
    cs->capacity = cs->capacity ? cs->capacity * 2 : 8;
    cs->data = (Frame *)realloc(cs->data, cs->capacity * sizeof(Frame));
  }
  cs->data[cs->count++] = f;
}

static Frame callstack_pop(CallStack *cs) {
  if (cs->count == 0) {
    fprintf(stderr, "call stack underflow\n");
    exit(1);
  }
  return cs->data[--cs->count];
}

static C0Value int_val(int32_t x) {
  C0Value v; v.kind = VAL_INT; v.as.i = x; return v;
}

static C0Value ptr_val(Pointer *p) {
  C0Value v; v.kind = VAL_PTR; v.as.p = p; return v;
}

static int32_t val2int(C0Value v) {
  if (v.kind != VAL_INT) {
    fprintf(stderr, "Invalid cast from pointer to integer\n");
    exit(1);
  }
  return v.as.i;
}

static Pointer *val2ptr(C0Value v) {
  if (v.kind != VAL_PTR) {
    fprintf(stderr, "Invalid cast from integer to pointer\n");
    exit(1);
  }
  return v.as.p;
}

static int32_t to_int32(int64_t v) {
  v &= 0xFFFFFFFFLL;
  if (v >= 0x80000000LL) v -= 0x100000000LL;
  return (int32_t)v;
}

static int32_t sign8(int32_t v) {
  v &= 0xFF;
  return v >= 0x80 ? v - 0x100 : v;
}

static int32_t sign16(int32_t v) {
  v &= 0xFFFF;
  return v >= 0x8000 ? v - 0x10000 : v;
}

static MemoryBlock *memblock_new(size_t size) {
  MemoryBlock *b = (MemoryBlock *)calloc(1, sizeof(MemoryBlock));
  b->bytes = (uint8_t *)calloc(size, 1);
  b->size = size;
  b->ptr_slots = NULL;
  b->ptr_slots_count = 0;
  return b;
}

static void memblock_write_int32(MemoryBlock *b, size_t offset, int32_t value) {
  uint32_t v = (uint32_t)value;
  if (offset + 3 >= b->size) return;
  b->bytes[offset] = v & 0xFF;
  b->bytes[offset + 1] = (v >> 8) & 0xFF;
  b->bytes[offset + 2] = (v >> 16) & 0xFF;
  b->bytes[offset + 3] = (v >> 24) & 0xFF;
}

static int32_t memblock_read_int32(MemoryBlock *b, size_t offset) {
  if (offset + 3 >= b->size) return 0;
  uint32_t v = b->bytes[offset] | (b->bytes[offset + 1] << 8) |
               (b->bytes[offset + 2] << 16) | (b->bytes[offset + 3] << 24);
  return to_int32(v);
}

static void memblock_write_byte(MemoryBlock *b, size_t offset, uint8_t value) {
  if (offset >= b->size) return;
  b->bytes[offset] = value;
}

static uint8_t memblock_read_byte(MemoryBlock *b, size_t offset) {
  if (offset >= b->size) return 0;
  return b->bytes[offset];
}

static void memblock_write_ptr(MemoryBlock *b, size_t offset, Pointer *value) {
  if (offset >= b->ptr_slots_count) {
    size_t new_count = offset + 1;
    b->ptr_slots = (Pointer **)realloc(b->ptr_slots, new_count * sizeof(Pointer *));
    for (size_t i = b->ptr_slots_count; i < new_count; i++) b->ptr_slots[i] = NULL;
    b->ptr_slots_count = new_count;
  }
  b->ptr_slots[offset] = value;
}

static Pointer *memblock_read_ptr(MemoryBlock *b, size_t offset) {
  if (offset >= b->ptr_slots_count) return NULL;
  return b->ptr_slots[offset];
}

static char *ptr_to_string(Pointer *p) {
  if (!p) return "";
  if (p->type != PTR_BLOCK) return "";
  MemoryBlock *b = (MemoryBlock *)p->obj;
  size_t idx = p->offset;
  size_t cap = 64;
  char *buf = (char *)malloc(cap);
  size_t len = 0;
  while (idx < b->size) {
    uint8_t byte = b->bytes[idx++];
    if (byte == 0) break;
    if (len + 2 >= cap) {
      cap *= 2;
      buf = (char *)realloc(buf, cap);
    }
    buf[len++] = (char)byte;
  }
  buf[len] = '\0';
  return buf;
}

static int opcode_size(const char *opcode) {
  if (!strcmp(opcode, "BIPUSH")) return 2;
  if (!strcmp(opcode, "ILDC")) return 3;
  if (!strcmp(opcode, "ALDC")) return 3;
  if (!strcmp(opcode, "VLOAD")) return 2;
  if (!strcmp(opcode, "VSTORE")) return 2;
  if (!strcmp(opcode, "GOTO")) return 3;
  if (!strcmp(opcode, "IF_CMPEQ") || !strcmp(opcode, "IF_CMPNE") || !strcmp(opcode, "IF_ICMPLT") ||
      !strcmp(opcode, "IF_ICMPLE") || !strcmp(opcode, "IF_ICMPGT") || !strcmp(opcode, "IF_ICMPGE")) return 3;
  if (!strcmp(opcode, "INVOKESTATIC") || !strcmp(opcode, "INVOKENATIVE")) return 3;
  if (!strcmp(opcode, "NEW") || !strcmp(opcode, "AADDF") || !strcmp(opcode, "NEWARRAY")) return 2;
  return 1;
}

static Instruction parse_instruction(JsonValue *ins) {
  Instruction i;
  JsonValue *pc = json_object_get(ins, "pc");
  JsonValue *opcode = json_object_get(ins, "opcode");
  JsonValue *operand = json_object_get(ins, "operand");

  i.pc = pc ? (int)pc->as.number : 0;
  i.opcode = opcode && opcode->type == JSON_STRING ? opcode->as.string : "";
  if (operand && operand->type == JSON_NUMBER) {
    i.has_operand = 1;
    i.operand = (int32_t)operand->as.number;
  } else {
    i.has_operand = 0;
    i.operand = 0;
  }
  return i;
}

static Function parse_function(JsonValue *fn) {
  Function f;
  JsonValue *num_args = json_object_get(fn, "num_args");
  JsonValue *num_vars = json_object_get(fn, "num_vars");
  JsonValue *code = json_object_get(fn, "code");
  f.num_args = num_args ? (int)num_args->as.number : 0;
  f.num_vars = num_vars ? (int)num_vars->as.number : 0;
  f.count = code ? code->as.array.count : 0;
  f.code = (Instruction *)calloc(f.count, sizeof(Instruction));
  f.max_pc = 0;
  for (size_t i = 0; i < f.count; i++) {
    f.code[i] = parse_instruction(code->as.array.items[i]);
    int size = opcode_size(f.code[i].opcode);
    int pc_end = f.code[i].pc + size;
    if (pc_end > f.max_pc) f.max_pc = pc_end;
  }
  f.pc_index = (int *)malloc((f.max_pc + 1) * sizeof(int));
  for (int i = 0; i <= f.max_pc; i++) f.pc_index[i] = -1;
  for (size_t i = 0; i < f.count; i++) {
    if (f.code[i].pc <= f.max_pc) f.pc_index[f.code[i].pc] = (int)i;
  }
  return f;
}

static Program parse_program(JsonValue *root) {
  Program p;
  memset(&p, 0, sizeof(Program));

  JsonValue *functions = json_object_get(root, "functions");
  JsonValue *int_pool = json_object_get(root, "int_pool");
  JsonValue *string_pool = json_object_get(root, "string_pool");

  if (!functions || functions->type != JSON_ARRAY) {
    fprintf(stderr, "program.functions missing\n");
    exit(1);
  }

  p.function_count = functions->as.array.count;
  p.functions = (Function *)calloc(p.function_count, sizeof(Function));
  for (size_t i = 0; i < p.function_count; i++) {
    p.functions[i] = parse_function(functions->as.array.items[i]);
  }

  if (int_pool && int_pool->type == JSON_ARRAY) {
    p.int_count = int_pool->as.array.count;
    p.int_pool = (int32_t *)calloc(p.int_count, sizeof(int32_t));
    for (size_t i = 0; i < p.int_count; i++) {
      p.int_pool[i] = (int32_t)int_pool->as.array.items[i]->as.number;
    }
  }

  if (string_pool && string_pool->type == JSON_ARRAY) {
    p.string_count = string_pool->as.array.count;
    p.string_pool = (Pointer **)calloc(p.string_count, sizeof(Pointer *));
    for (size_t i = 0; i < p.string_count; i++) {
      JsonValue *s = string_pool->as.array.items[i];
      const char *str = s->type == JSON_STRING ? s->as.string : "";
      size_t len = strlen(str);
      MemoryBlock *b = memblock_new(len + 1);
      for (size_t j = 0; j < len; j++) memblock_write_byte(b, j, (uint8_t)str[j]);
      memblock_write_byte(b, len, 0);
      Pointer *ptr = (Pointer *)calloc(1, sizeof(Pointer));
      ptr->type = PTR_BLOCK;
      ptr->obj = b;
      ptr->offset = 0;
      p.string_pool[i] = ptr;
    }
  }

  return p;
}

static Instruction *fetch_instruction(Function *fn, int pc) {
  if (pc < 0 || pc > fn->max_pc) return NULL;
  int idx = fn->pc_index[pc];
  if (idx < 0) return NULL;
  return &fn->code[idx];
}

int main() {
  // read stdin (stream-safe)
  size_t cap = 4096;
  size_t len = 0;
  char *input = (char *)malloc(cap);
  if (!input) {
    fprintf(stderr, "allocation failed\n");
    return 1;
  }
  size_t n = 0;
  while ((n = fread(input + len, 1, cap - len, stdin)) > 0) {
    len += n;
    if (cap - len == 0) {
      cap *= 2;
      char *next = (char *)realloc(input, cap);
      if (!next) {
        fprintf(stderr, "allocation failed\n");
        free(input);
        return 1;
      }
      input = next;
    }
  }
  if (len == 0) {
    fprintf(stderr, "no input\n");
    free(input);
    return 1;
  }
  input[len] = '\0';

  JsonValue *root = json_parse(input);
  if (!root) {
    fprintf(stderr, "invalid json\n");
    return 1;
  }

  JsonValue *program_obj = json_object_get(root, "program");
  if (!program_obj) {
    fprintf(stderr, "missing program field\n");
    return 1;
  }

  Program program = parse_program(program_obj);

  Function *fn = &program.functions[0];
  Stack stack; stack_init(&stack);
  CallStack callstack; callstack_init(&callstack);

  int locals_count = fn->num_args + fn->num_vars;
  C0Value *locals = (C0Value *)calloc(locals_count, sizeof(C0Value));
  for (int i = 0; i < locals_count; i++) locals[i] = int_val(0);

  int pc = 0;
  int64_t instruction_count = 0;
  int max_stack_depth = 0;

  clock_t start = clock();

  while (1) {
    Instruction *ins = fetch_instruction(fn, pc);
    if (!ins) {
      fprintf(stderr, "invalid pc %d\n", pc);
      return 1;
    }

    instruction_count++;

    const char *op = ins->opcode;
    int32_t operand = ins->operand;

    if (!strcmp(op, "POP")) {
      pc += 1;
      stack_pop(&stack);
    } else if (!strcmp(op, "DUP")) {
      pc += 1;
      C0Value v = stack_pop(&stack);
      stack_push(&stack, v);
      stack_push(&stack, v);
    } else if (!strcmp(op, "SWAP")) {
      pc += 1;
      C0Value v2 = stack_pop(&stack);
      C0Value v1 = stack_pop(&stack);
      stack_push(&stack, v2);
      stack_push(&stack, v1);
    } else if (!strcmp(op, "RETURN")) {
      C0Value retv = stack_pop(&stack);
      if (callstack.count == 0) {
        int32_t retval = val2int(retv);
        clock_t end = clock();
        double duration_ms = (double)(end - start) * 1000.0 / CLOCKS_PER_SEC;

        printf("{\"result\":{\"return_value\":%d,\"output\":[]},", retval);
        printf("\"metrics\":{");
        printf("\"execution_time_ms\":%.3f,", duration_ms);
        printf("\"instruction_count\":%lld,", (long long)instruction_count);
        printf("\"max_stack_depth\":%d,", max_stack_depth);
        printf("\"runtime\":\"c\"}}\n");
        return 0;
      } else {
        Frame frame = callstack_pop(&callstack);
        free(locals);
        locals = frame.locals;
        locals_count = frame.locals_count;
        fn = frame.func;
        pc = frame.pc;
        stack = frame.stack;
        stack_push(&stack, retv);
      }
    } else if (!strcmp(op, "IADD")) {
      pc += 1;
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      stack_push(&stack, int_val(to_int32(x + y)));
    } else if (!strcmp(op, "ISUB")) {
      pc += 1;
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      stack_push(&stack, int_val(to_int32(x - y)));
    } else if (!strcmp(op, "IMUL")) {
      pc += 1;
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      stack_push(&stack, int_val(to_int32(x * y)));
    } else if (!strcmp(op, "IDIV")) {
      pc += 1;
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      if (y == 0) { fprintf(stderr, "Division by zero\n"); return 1; }
      stack_push(&stack, int_val(to_int32(x / y)));
    } else if (!strcmp(op, "IREM")) {
      pc += 1;
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      if (y == 0) { fprintf(stderr, "Remainder by zero\n"); return 1; }
      stack_push(&stack, int_val(to_int32(x % y)));
    } else if (!strcmp(op, "IAND")) {
      pc += 1;
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      stack_push(&stack, int_val(to_int32(x & y)));
    } else if (!strcmp(op, "IOR")) {
      pc += 1;
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      stack_push(&stack, int_val(to_int32(x | y)));
    } else if (!strcmp(op, "IXOR")) {
      pc += 1;
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      stack_push(&stack, int_val(to_int32(x ^ y)));
    } else if (!strcmp(op, "ISHL")) {
      pc += 1;
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      if (y < 0 || y >= 32) { fprintf(stderr, "Shift out of range\n"); return 1; }
      stack_push(&stack, int_val(to_int32(x << y)));
    } else if (!strcmp(op, "ISHR")) {
      pc += 1;
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      if (y < 0 || y >= 32) { fprintf(stderr, "Shift out of range\n"); return 1; }
      stack_push(&stack, int_val(to_int32(x >> y)));
    } else if (!strcmp(op, "BIPUSH")) {
      stack_push(&stack, int_val(sign8(operand)));
      pc += 2;
    } else if (!strcmp(op, "ILDC")) {
      if ((size_t)operand >= program.int_count) { fprintf(stderr, "invalid int pool\n"); return 1; }
      stack_push(&stack, int_val(program.int_pool[operand]));
      pc += 3;
    } else if (!strcmp(op, "ALDC")) {
      if ((size_t)operand >= program.string_count) { fprintf(stderr, "invalid string pool\n"); return 1; }
      stack_push(&stack, ptr_val(program.string_pool[operand]));
      pc += 3;
    } else if (!strcmp(op, "ACONST_NULL")) {
      stack_push(&stack, ptr_val(NULL));
      pc += 1;
    } else if (!strcmp(op, "VLOAD")) {
      stack_push(&stack, locals[operand]);
      pc += 2;
    } else if (!strcmp(op, "VSTORE")) {
      locals[operand] = stack_pop(&stack);
      pc += 2;
    } else if (!strcmp(op, "ATHROW")) {
      Pointer *p = val2ptr(stack_pop(&stack));
      char *msg = ptr_to_string(p);
      fprintf(stderr, "%s\n", msg);
      free(msg);
      return 1;
    } else if (!strcmp(op, "ASSERT")) {
      Pointer *p = val2ptr(stack_pop(&stack));
      char *msg = ptr_to_string(p);
      int32_t x = val2int(stack_pop(&stack));
      if (x == 0) { fprintf(stderr, "%s\n", msg); free(msg); return 1; }
      free(msg);
      pc += 1;
    } else if (!strcmp(op, "NOP")) {
      pc += 1;
    } else if (!strcmp(op, "IF_CMPEQ")) {
      C0Value v2 = stack_pop(&stack);
      C0Value v1 = stack_pop(&stack);
      int offset = sign16(operand);
      if (v1.kind == v2.kind &&
          ((v1.kind == VAL_INT && v1.as.i == v2.as.i) ||
           (v1.kind == VAL_PTR && v1.as.p == v2.as.p))) {
        pc = pc + offset;
      } else {
        pc += 3;
      }
    } else if (!strcmp(op, "IF_CMPNE")) {
      C0Value v2 = stack_pop(&stack);
      C0Value v1 = stack_pop(&stack);
      int offset = sign16(operand);
      int eq = (v1.kind == v2.kind &&
                ((v1.kind == VAL_INT && v1.as.i == v2.as.i) ||
                 (v1.kind == VAL_PTR && v1.as.p == v2.as.p)));
      if (!eq) pc = pc + offset;
      else pc += 3;
    } else if (!strcmp(op, "IF_ICMPLT")) {
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      int offset = sign16(operand);
      if (x < y) pc = pc + offset; else pc += 3;
    } else if (!strcmp(op, "IF_ICMPLE")) {
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      int offset = sign16(operand);
      if (x <= y) pc = pc + offset; else pc += 3;
    } else if (!strcmp(op, "IF_ICMPGT")) {
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      int offset = sign16(operand);
      if (x > y) pc = pc + offset; else pc += 3;
    } else if (!strcmp(op, "IF_ICMPGE")) {
      int32_t y = val2int(stack_pop(&stack));
      int32_t x = val2int(stack_pop(&stack));
      int offset = sign16(operand);
      if (x >= y) pc = pc + offset; else pc += 3;
    } else if (!strcmp(op, "GOTO")) {
      int offset = sign16(operand);
      pc = pc + offset;
    } else if (!strcmp(op, "INVOKESTATIC")) {
      int index = operand;
      if (index < 0 || (size_t)index >= program.function_count) { fprintf(stderr, "bad function index\n"); return 1; }
      Function *target = &program.functions[index];
      int new_locals_count = target->num_args + target->num_vars;
      C0Value *new_locals = (C0Value *)calloc(new_locals_count, sizeof(C0Value));
      for (int i = new_locals_count - 1; i >= 0; i--) new_locals[i] = int_val(0);
      for (int i = target->num_args - 1; i >= 0; i--) {
        new_locals[i] = stack_pop(&stack);
      }
      Frame frame;
      frame.stack = stack;
      frame.func = fn;
      frame.pc = pc + 3;
      frame.locals = locals;
      frame.locals_count = locals_count;
      callstack_push(&callstack, frame);

      stack_init(&stack);
      fn = target;
      pc = 0;
      locals = new_locals;
      locals_count = new_locals_count;
    } else if (!strcmp(op, "INVOKENATIVE")) {
      fprintf(stderr, "native functions not supported\n");
      return 1;
    } else if (!strcmp(op, "NEW")) {
      MemoryBlock *b = memblock_new((size_t)operand);
      Pointer *p = (Pointer *)calloc(1, sizeof(Pointer));
      p->type = PTR_BLOCK;
      p->obj = b;
      p->offset = 0;
      stack_push(&stack, ptr_val(p));
      pc += 2;
    } else if (!strcmp(op, "IMLOAD")) {
      pc += 1;
      Pointer *p = val2ptr(stack_pop(&stack));
      if (!p) { fprintf(stderr, "imload on NULL\n"); return 1; }
      MemoryBlock *b = (MemoryBlock *)p->obj;
      stack_push(&stack, int_val(memblock_read_int32(b, p->offset)));
    } else if (!strcmp(op, "IMSTORE")) {
      pc += 1;
      int32_t v = val2int(stack_pop(&stack));
      Pointer *p = val2ptr(stack_pop(&stack));
      if (!p) { fprintf(stderr, "imstore on NULL\n"); return 1; }
      MemoryBlock *b = (MemoryBlock *)p->obj;
      memblock_write_int32(b, p->offset, v);
    } else if (!strcmp(op, "AMLOAD")) {
      pc += 1;
      Pointer *p = val2ptr(stack_pop(&stack));
      if (!p) { fprintf(stderr, "amload on NULL\n"); return 1; }
      MemoryBlock *b = (MemoryBlock *)p->obj;
      Pointer *slot = memblock_read_ptr(b, p->offset);
      stack_push(&stack, ptr_val(slot));
    } else if (!strcmp(op, "AMSTORE")) {
      pc += 1;
      Pointer *to_store = val2ptr(stack_pop(&stack));
      Pointer *p = val2ptr(stack_pop(&stack));
      if (!p) { fprintf(stderr, "amstore on NULL\n"); return 1; }
      MemoryBlock *b = (MemoryBlock *)p->obj;
      memblock_write_ptr(b, p->offset, to_store);
    } else if (!strcmp(op, "CMLOAD")) {
      pc += 1;
      Pointer *p = val2ptr(stack_pop(&stack));
      if (!p) { fprintf(stderr, "cmload on NULL\n"); return 1; }
      MemoryBlock *b = (MemoryBlock *)p->obj;
      stack_push(&stack, int_val(memblock_read_byte(b, p->offset)));
    } else if (!strcmp(op, "CMSTORE")) {
      pc += 1;
      int32_t v = val2int(stack_pop(&stack));
      Pointer *p = val2ptr(stack_pop(&stack));
      if (!p) { fprintf(stderr, "cmstore on NULL\n"); return 1; }
      MemoryBlock *b = (MemoryBlock *)p->obj;
      memblock_write_byte(b, p->offset, (uint8_t)(v & 0x7F));
    } else if (!strcmp(op, "AADDF")) {
      Pointer *p = val2ptr(stack_pop(&stack));
      if (!p) { fprintf(stderr, "aaddf on NULL\n"); return 1; }
      Pointer *np = (Pointer *)calloc(1, sizeof(Pointer));
      np->type = PTR_BLOCK;
      np->obj = p->obj;
      np->offset = p->offset + operand;
      stack_push(&stack, ptr_val(np));
      pc += 2;
    } else if (!strcmp(op, "NEWARRAY")) {
      int32_t cap = val2int(stack_pop(&stack));
      if (cap < 0) { fprintf(stderr, "invalid size\n"); return 1; }
      if (cap == 0) {
        stack_push(&stack, ptr_val(NULL));
      } else {
        ArrayObject *arr = (ArrayObject *)calloc(1, sizeof(ArrayObject));
        arr->count = cap;
        arr->elt_size = operand;
        arr->elems = memblock_new((size_t)cap * (size_t)operand);
        Pointer *p = (Pointer *)calloc(1, sizeof(Pointer));
        p->type = PTR_ARRAY;
        p->obj = arr;
        p->offset = 0;
        stack_push(&stack, ptr_val(p));
      }
      pc += 2;
    } else if (!strcmp(op, "ARRAYLENGTH")) {
      pc += 1;
      Pointer *p = val2ptr(stack_pop(&stack));
      int32_t n = 0;
      if (p && p->type == PTR_ARRAY) {
        ArrayObject *arr = (ArrayObject *)p->obj;
        n = arr->count;
      }
      stack_push(&stack, int_val(n));
    } else if (!strcmp(op, "AADDS")) {
      pc += 1;
      int32_t i = val2int(stack_pop(&stack));
      Pointer *p = val2ptr(stack_pop(&stack));
      if (!p || p->type != PTR_ARRAY) { fprintf(stderr, "aadds on NULL array\n"); return 1; }
      ArrayObject *arr = (ArrayObject *)p->obj;
      if (i < 0 || i >= arr->count) { fprintf(stderr, "array index out of bounds\n"); return 1; }
      size_t offset = (size_t)i * (size_t)arr->elt_size;
      Pointer *np = (Pointer *)calloc(1, sizeof(Pointer));
      np->type = PTR_BLOCK;
      np->obj = arr->elems;
      np->offset = offset;
      stack_push(&stack, ptr_val(np));
    } else {
      fprintf(stderr, "unsupported opcode %s\n", op);
      return 1;
    }

    if ((int)stack.count > max_stack_depth) max_stack_depth = (int)stack.count;
  }

  return 0;
}
