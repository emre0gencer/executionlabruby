# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Rails 8.1 educational platform for executing C0 bytecode programs across multiple virtual machine runtimes (Ruby, Node.js, Native C). Users create bytecode programs via assembly or JSON, execute them on different VMs, and inspect detailed execution traces.

## Commands

```bash
bin/dev                                             # Start Puma server (port 3000)
bin/rails db:seed                                   # Load 20+ example programs and 3 runtimes
bin/rails db:seed:replant                           # Reset and reseed database
bin/rails console                                   # REPL for testing models/services

bin/rails test                                      # Run all tests (minitest)
bin/rails test test/models/program_test.rb          # Single test file
bin/ci                                              # Full CI suite: setup, rubocop, bundler-audit, importmap audit, brakeman, tests
```

### Native Runtime Compilation (optional)
```bash
gcc -O2 native_runtime/c0vm_runner.c -o c0vm_runner
# Then update Runtime config: { "executable_path" => "/abs/path/to/c0vm_runner" }
```

## Architecture

### Domain Models
- **Program**: Stores C0 bytecode as JSON with deep validation (function structure, PC sequencing, operand ranges per opcode)
- **Runtime**: Execution adapter config — `adapter_class` points to `ExecutionLab::Runtimes::*`, `config` JSON holds runtime-specific settings
- **Execution**: Result record — status (`pending|running|completed|failed`), `result`, `metrics` (`instruction_count`, `elapsed_time_ms`), and optional traces
- **ExecutionTrace**: Step-by-step VM state snapshots indexed by `(execution_id, step)`

### Service Layer (`app/services/execution_lab/`)
- **ExecutionEngine**: Orchestrator — validates instruction set match between Program and Runtime, creates Execution record, calls adapter, persists traces
- **BytecodeParser**: Parses C0 assembly text into bytecode JSON — handles label resolution, PC calculation (accounting for multi-byte opcodes), and pool directives (`.int`, `.string`, `.native`)
- **RuntimeInterface**: Abstract contract all adapters must implement (`run`, `step`, `state`, `metrics`)
- **VM Adapters**:
  - `RubyC0VM` — pure Ruby implementation (~705 lines), full stack/heap/frame simulation
  - `NodeC0VM` — shells out to `node_c0_vm.js` via stdin/stdout JSON IPC
  - `NativeC0VM` — calls compiled C binary via `Open3.capture3` JSON IPC

### Data Flow
1. `ProgramsController#create` receives assembly text → `apply_assembly_source` calls `BytecodeParser.new.parse(assembly)` → overwrites `:bytecode` param
2. `ExecutionsController#create` → `ExecutionEngine.new(program, runtime).run`
3. Engine validates instruction sets match, calls `adapter.run(bytecode, record_trace:)`
4. Adapter returns `{result:, metrics:, trace:}` hash
5. Engine persists `ExecutionTrace` records (if `record_trace: true`) and updates Execution status

### Bytecode JSON Structure
```json
{
  "instruction_set": "c0-vm",
  "int_pool": [1000],
  "string_pool": ["hello"],
  "native_pool": [{ "num_args": 2, "function_table_index": 0 }],
  "functions": [{
    "name": "main",
    "num_args": 0,
    "num_vars": 3,
    "code": [
      { "pc": 0, "opcode": "BIPUSH", "operand": 1 },
      { "pc": 2, "opcode": "RETURN" }
    ]
  }]
}
```
PCs must be sequential accounting for `Program::OPCODE_SIZES` (e.g., `BIPUSH` is 2 bytes, `GOTO` is 3 bytes).

### VM Error Hierarchy
All adapters raise `ExecutionLab::VMError` (not `StandardError`) — subclasses: `UserError`, `AssertionFailure`, `MemoryError`, `ValueError`, `ArithmeticError`. Errors bubble up to `ExecutionEngine` which catches and marks the Execution as failed.

## Key Conventions

- **Always use `BytecodeParser`** instead of hand-writing bytecode JSON — the parser handles PC offsets and label resolution correctly
- **Controller params**: `ProgramsController` accepts `:bytecode` as either a JSON string or parsed hash (see `normalized_program_params`); uses Rails 8 `params.expect()` for required params
- **Adapters must not catch `VMError`** — let it bubble to `ExecutionEngine`
- **No instruction set logic in controllers** — keep it in models/services
- **Bytecode validation uses custom validators** (not built-in Rails validators) in `Program` model, checking opcodes against `Program::VALID_OPCODES` and operand ranges per opcode

## Anti-Patterns to Avoid
- Don't validate opcodes outside `Program::VALID_OPCODES` constant
- Don't manually set PC offsets — use `BytecodeParser`
- Don't add instruction set matching logic to controllers
- Don't catch `ExecutionLab::VMError` inside adapters
