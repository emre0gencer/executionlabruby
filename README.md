# Execution Lab

An educational platform for executing C0 bytecode programs across multiple virtual machine runtimes and comparing execution metrics. Built with Rails 8.1.

## Features

- **Multi-runtime execution** — run the same program on Ruby, Node.js, or Native C VM adapters
- **Step-through debugger** — inspect operand stack, local variables, and call stack at every instruction
- **Cross-runtime comparison** — side-by-side result and metric comparison across all compatible runtimes
- **Assembly compiler** — write C0 assembly text and compile it to bytecode automatically (handles label resolution and PC offsets)
- **Deep bytecode validation** — programs are validated against opcode specs including operand range checks

## Requirements

- Ruby 3.4+
- Node.js (for the Node.js VM adapter)
- SQLite3

## Setup

```bash
bundle install
bin/rails db:migrate
bin/rails db:seed        # loads 20+ example programs and 3 runtimes
bin/dev                  # starts server at http://localhost:3000
```

### Optional: Native C runtime

```bash
gcc -O2 native_runtime/c0vm_runner.c -o c0vm_runner
# Then update the NativeC0VM Runtime record's config:
# { "executable_path" => "/absolute/path/to/c0vm_runner" }
```

## Usage

1. Browse or create a program at `/programs`
2. Click **Run on Runtime** to execute and optionally record a trace
3. Use the **Step-through Debugger** on the execution page to walk through VM state
4. Click **Compare All Runtimes** to run the program on every compatible runtime simultaneously

## Architecture

### Domain Models

| Model | Purpose |
|---|---|
| `Program` | Stores C0 bytecode JSON with deep validation |
| `Runtime` | Adapter config — points to an `ExecutionLab::Runtimes::*` class |
| `Execution` | Result record — status, result, metrics, error |
| `ExecutionTrace` | Step-by-step VM snapshots indexed by `(execution_id, step)` |

### VM Adapters (`app/services/execution_lab/runtimes/`)

- **`RubyC0VM`** — pure Ruby implementation (~705 lines), full stack/heap/frame simulation
- **`NodeC0VM`** — shells out to `node_c0_vm.js` via stdin/stdout JSON IPC
- **`NativeC0VM`** — calls a compiled C binary via `Open3.capture3` JSON IPC

### Bytecode Format

```json
{
  "instruction_set": "c0-vm",
  "int_pool": [1000],
  "string_pool": ["hello"],
  "native_pool": [{ "num_args": 2, "function_table_index": 0 }],
  "functions": [{
    "name": "main",
    "num_args": 0,
    "num_vars": 2,
    "code": [
      { "pc": 0, "opcode": "BIPUSH", "operand": 1 },
      { "pc": 2, "opcode": "RETURN" }
    ]
  }]
}
```

Or write assembly and let `BytecodeParser` handle it:

```
bipush 1
bipush 2
iadd
return
```

## Development

```bash
bin/rails test           # run all tests (minitest)
bin/ci                   # full CI: rubocop, bundler-audit, importmap audit, brakeman, tests
bundle exec rubocop      # linting
```

## Tech Stack

- **Rails 8.1** — Hotwire (Turbo + Stimulus), SQLite, Propshaft
- **Tailwind CSS v4** — dark theme UI
- **Stimulus controllers** — `TraceDebugger`, `Tabs`, `Flash`
