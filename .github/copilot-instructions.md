# Execution Lab Ruby - AI Coding Agent Instructions

## Project Overview
A Rails 8.1 educational platform for executing C0 bytecode programs across multiple virtual machine runtimes (Ruby, Node.js, Native C). Users create bytecode programs via assembly or JSON, execute them on different VMs, and inspect detailed execution traces.

## Core Architecture

### Three-Model Domain
- **Program**: Stores bytecode (JSON) and validates structure against C0 instruction set (~40 opcodes: `IADD`, `BIPUSH`, `VLOAD`, etc.)
- **Runtime**: Defines execution adapters (Ruby/Node/Native) with `adapter_class` pointing to `ExecutionLab::Runtimes::*`
- **Execution**: Result of running a Program on a Runtime, with metrics, traces, and status (`pending|running|completed|failed`)

### Service Layer Pattern
All VM execution logic lives in `app/services/execution_lab/`:
- `ExecutionEngine`: Orchestrates execution, validates instruction set match, persists results
- `BytecodeParser`: Parses C0 assembly (`.int`, `FUNC`, labels) into structured bytecode JSON
- `RuntimeInterface`: Interface that all adapters must implement (`run`, `step`, `state`, `metrics`)
- `runtimes/*`: VM adapters - `RubyC0VM` (pure Ruby), `NodeC0VM` (shell out to JS), `NativeC0VM` (C binary via JSON stdin)

### Critical Data Flow
1. User submits assembly via `ProgramsController#create` → `apply_assembly_source` parses to bytecode
2. `ExecutionsController#create` → `ExecutionEngine.new(program, runtime).run`
3. Engine validates instruction sets match, calls adapter's `#run(bytecode, record_trace:)`
4. Adapter returns `{result:, metrics:, trace:}` hash
5. Engine persists execution + optional `ExecutionTrace` records (step-by-step PC/opcode/snapshot)

## Bytecode Structure
Programs use nested JSON validated in [app/models/program.rb](app/models/program.rb):
```ruby
{
  "functions" => [
    {
      "name" => "main",
      "num_args" => 0,
      "num_vars" => 3,
      "code" => [
        { "pc" => 0, "opcode" => "BIPUSH", "operand" => 1 },
        { "pc" => 2, "opcode" => "RETURN" }
      ]
    }
  ],
  "int_pool" => [1000],
  "string_pool" => ["hello"],
  "native_pool" => []
}
```
PC must be sequential and account for opcode sizes (see `Program::OPCODE_SIZES`).

## Key Conventions

### Assembly Parser Usage
When working with bytecode, **always** use `BytecodeParser.new.parse(assembly_text)` instead of hand-writing JSON. Parser handles:
- Label resolution (e.g., `loop:` → PC offset)
- PC calculation accounting for multi-byte opcodes
- Pool directives (`.int`, `.string`, `.native`)

### Runtime Adapter Contract
All adapters in `app/services/execution_lab/runtimes/` must:
- Include `ExecutionLab::RuntimeInterface`
- Accept `runtime:` in constructor (for config access like `executable_path`)
- Return `{result:, metrics:, trace:}` hash from `#run`
- Raise `ExecutionLab::VMError` for VM-level failures (not StandardError)

### Controller Parameter Handling
- `ProgramsController` accepts both JSON string and parsed hash for `:bytecode` (see `normalized_program_params`)
- `apply_assembly_source` auto-parses `:assembly_source` if present, overwriting `:bytecode`
- Use `params.expect(:key)` for required parameters (Rails 8 strong params)

## Development Workflows

### Running the App
```bash
bin/dev                    # Start Puma server
bin/rails db:seed         # Load 20+ example programs and 3 runtimes
bin/rails console         # REPL for testing models/services
```

### Testing
```bash
bin/rails test                                      # Run all tests (minitest)
bin/rails test test/models/program_test.rb         # Single file
bin/ci                                              # Full CI suite (runs tests, brakeman, rubocop)
```

### Native Runtime Setup
The `NativeC0VM` adapter requires compiling [native_runtime/c0vm_runner.c](native_runtime/c0vm_runner.c):
```bash
gcc -O2 native_runtime/c0vm_runner.c -o c0vm_runner
# Update Runtime config: { "executable_path" => "/abs/path/to/c0vm_runner" }
```
Binary reads JSON via stdin, writes `{result, metrics, trace}` to stdout.

## Common Patterns

### Validating Bytecode
Models use custom validators (not built-in Rails validators) to recursively check:
- Function structure (`num_args`, `num_vars`, non-empty `code`)
- Instruction fields (`pc`, `opcode`, `operand`)
- PC sequencing and operand ranges (e.g., `BIPUSH` must be -128..127)

### Execution Tracing
When `record_trace: true`, adapters must return array in `trace:`:
```ruby
[
  { pc: 0, opcode: "BIPUSH", stack: [1], locals: [], ... },
  { pc: 2, opcode: "RETURN", stack: [], locals: [], ... }
]
```
Engine persists to `execution_traces` with `step` index.

### Multi-Runtime Support
Same bytecode runs on all runtimes if instruction sets match. Compare:
- `RubyC0VM`: Full 705-line Ruby VM with stack/heap/frames in memory
- `NodeC0VM`: Shells out to Node.js script (see [app/services/execution_lab/runtimes/node_c0_vm.js](app/services/execution_lab/runtimes/node_c0_vm.js))
- `NativeC0VM`: Compiles to C for speed, uses `Open3.capture3` for IPC

## File Locations Reference
- **Models**: [app/models/](app/models/) - `Program`, `Runtime`, `Execution`, `ExecutionTrace`
- **Controllers**: [app/controllers/](app/controllers/) - Standard Rails CRUD + `ExecutionsController`
- **Services**: [app/services/execution_lab/](app/services/execution_lab/) - All VM/parsing logic
- **Seeds**: [db/seeds.rb](db/seeds.rb) - 20+ example programs (factorial, fibonacci, linked lists)
- **Routes**: RESTful resources + `root "programs#index"` ([config/routes.rb](config/routes.rb))

## Anti-Patterns to Avoid
- Don't validate opcodes outside `Program::VALID_OPCODES` constant
- Don't create bytecode JSON manually - use `BytecodeParser`
- Don't catch `ExecutionLab::VMError` in adapters - let it bubble to `ExecutionEngine`
- Don't add instruction set logic to controllers - keep in models/services
- Don't modify PC offsets manually - parser calculates from opcode sizes
