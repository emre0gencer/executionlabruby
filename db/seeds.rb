# Default C0 runtime
Runtime.find_or_create_by!(name: "Ruby C0 VM") do |runtime|
	runtime.instruction_set = "c0-vm"
	runtime.adapter_class = "ExecutionLab::Runtimes::RubyC0VM"
	runtime.config = {}
end

Runtime.find_or_create_by!(name: "Node.js C0 VM") do |runtime|
	runtime.instruction_set = "c0-vm"
	runtime.adapter_class = "ExecutionLab::Runtimes::NodeC0VM"
	runtime.config = {}
end

Runtime.find_or_create_by!(name: "Native C C0 VM") do |runtime|
	runtime.instruction_set = "c0-vm"
	runtime.adapter_class = "ExecutionLab::Runtimes::NativeC0VM"
	runtime.config = { "executable_path" => "C:/path/to/c0vm_runner.exe" }
end

parser = ExecutionLab::BytecodeParser.new

def seed_program(parser, name, description, asm)
	program = Program.find_or_initialize_by(name: name)
	program.description = description
	program.instruction_set = "c0-vm"
	program.bytecode = parser.parse(asm)
	program.save!
end

seed_program(
	parser,
	"Integer Summation Loop",
	"Sums integers from 1..N using a tight loop with arithmetic and branches.",
	<<~ASM
		.int 1000
		FUNC main 0 3
		ILDC 0
		VSTORE 0
		BIPUSH 1
		VSTORE 1
		BIPUSH 0
		VSTORE 2
		loop:
		VLOAD 1
		VLOAD 0
		IF_ICMPGT end
		VLOAD 2
		VLOAD 1
		IADD
		VSTORE 2
		VLOAD 1
		BIPUSH 1
		IADD
		VSTORE 1
		GOTO loop
		end:
		VLOAD 2
		RETURN
		END
	ASM
)

seed_program(
	parser,
	"Fibonacci Iterative",
	"Computes fib(N) iteratively with branching and repeated updates.",
	<<~ASM
		.int 30
		FUNC main 0 5
		ILDC 0
		VSTORE 0
		BIPUSH 0
		VSTORE 1
		BIPUSH 1
		VSTORE 2
		BIPUSH 0
		VSTORE 3
		loop:
		VLOAD 3
		VLOAD 0
		IF_ICMPGE end
		VLOAD 1
		VLOAD 2
		IADD
		VSTORE 4
		VLOAD 2
		VSTORE 1
		VLOAD 4
		VSTORE 2
		VLOAD 3
		BIPUSH 1
		IADD
		VSTORE 3
		GOTO loop
		end:
		VLOAD 1
		RETURN
		END
	ASM
)

seed_program(
	parser,
	"Factorial Loop",
	"Loop-based factorial to stress multiplication throughput and branch control.",
	<<~ASM
		.int 10
		FUNC main 0 3
		ILDC 0
		VSTORE 0
		BIPUSH 1
		VSTORE 1
		BIPUSH 1
		VSTORE 2
		loop:
		VLOAD 1
		VLOAD 0
		IF_ICMPGT end
		VLOAD 2
		VLOAD 1
		IMUL
		VSTORE 2
		VLOAD 1
		BIPUSH 1
		IADD
		VSTORE 1
		GOTO loop
		end:
		VLOAD 2
		RETURN
		END
	ASM
)

seed_program(
	parser,
	"Array Allocation + Traversal",
	"Allocates an int array, fills it, then sums elements to stress memory access.",
	<<~ASM
		.int 200
		FUNC main 0 4
		ILDC 0
		VSTORE 0
		VLOAD 0
		NEWARRAY 4
		VSTORE 1
		BIPUSH 0
		VSTORE 2
		BIPUSH 0
		VSTORE 3
		fill:
		VLOAD 2
		VLOAD 0
		IF_ICMPGE fill_done
		VLOAD 1
		VLOAD 2
		AADDS
		VLOAD 2
		IMSTORE
		VLOAD 2
		BIPUSH 1
		IADD
		VSTORE 2
		GOTO fill
		fill_done:
		BIPUSH 0
		VSTORE 2
		sumloop:
		VLOAD 2
		VLOAD 0
		IF_ICMPGE end
		VLOAD 1
		VLOAD 2
		AADDS
		IMLOAD
		VLOAD 3
		IADD
		VSTORE 3
		VLOAD 2
		BIPUSH 1
		IADD
		VSTORE 2
		GOTO sumloop
		end:
		VLOAD 3
		RETURN
		END
	ASM
)

seed_program(
	parser,
	"Bubble Sort (Fixed Size)",
	"Sorts eight integers with nested loops, stressing control flow and memory writes.",
	<<~ASM
		FUNC main 0 6
		BIPUSH 8
		VSTORE 0
		VLOAD 0
		NEWARRAY 4
		VSTORE 1
		VLOAD 1
		BIPUSH 0
		AADDS
		BIPUSH 9
		IMSTORE
		VLOAD 1
		BIPUSH 1
		AADDS
		BIPUSH 3
		IMSTORE
		VLOAD 1
		BIPUSH 2
		AADDS
		BIPUSH 7
		IMSTORE
		VLOAD 1
		BIPUSH 3
		AADDS
		BIPUSH 1
		IMSTORE
		VLOAD 1
		BIPUSH 4
		AADDS
		BIPUSH 8
		IMSTORE
		VLOAD 1
		BIPUSH 5
		AADDS
		BIPUSH 2
		IMSTORE
		VLOAD 1
		BIPUSH 6
		AADDS
		BIPUSH 5
		IMSTORE
		VLOAD 1
		BIPUSH 7
		AADDS
		BIPUSH 4
		IMSTORE
		BIPUSH 0
		VSTORE 2
		outer:
		VLOAD 2
		VLOAD 0
		BIPUSH 1
		ISUB
		IF_ICMPGE end
		BIPUSH 0
		VSTORE 3
		inner:
		VLOAD 3
		VLOAD 0
		BIPUSH 1
		ISUB
		VLOAD 2
		ISUB
		IF_ICMPGE next_i
		VLOAD 1
		VLOAD 3
		AADDS
		IMLOAD
		VSTORE 4
		VLOAD 1
		VLOAD 3
		BIPUSH 1
		IADD
		AADDS
		IMLOAD
		VSTORE 5
		VLOAD 4
		VLOAD 5
		IF_ICMPLE no_swap
		VLOAD 1
		VLOAD 3
		AADDS
		VLOAD 5
		IMSTORE
		VLOAD 1
		VLOAD 3
		BIPUSH 1
		IADD
		AADDS
		VLOAD 4
		IMSTORE
		no_swap:
		VLOAD 3
		BIPUSH 1
		IADD
		VSTORE 3
		GOTO inner
		next_i:
		VLOAD 2
		BIPUSH 1
		IADD
		VSTORE 2
		GOTO outer
		end:
		VLOAD 1
		BIPUSH 0
		AADDS
		IMLOAD
		RETURN
		END
	ASM
)

seed_program(
	parser,
	"Conditional Stress Test",
	"Deep if/else chains based on modulus to stress branching and comparisons.",
	<<~ASM
		.int 500
		FUNC main 0 4
		ILDC 0
		VSTORE 0
		BIPUSH 0
		VSTORE 1
		BIPUSH 0
		VSTORE 2
		loop:
		VLOAD 1
		VLOAD 0
		IF_ICMPGE end
		VLOAD 1
		BIPUSH 3
		IREM
		VSTORE 3
		VLOAD 3
		BIPUSH 0
		IF_CMPEQ case0
		VLOAD 3
		BIPUSH 1
		IF_CMPEQ case1
		VLOAD 2
		VLOAD 1
		BIPUSH 2
		IMUL
		IADD
		VSTORE 2
		GOTO after_case
		case0:
		VLOAD 2
		VLOAD 1
		IADD
		VSTORE 2
		GOTO after_case
		case1:
		VLOAD 2
		VLOAD 1
		ISUB
		VSTORE 2
		after_case:
		VLOAD 1
		BIPUSH 1
		IADD
		VSTORE 1
		GOTO loop
		end:
		VLOAD 2
		RETURN
		END
	ASM
)

seed_program(
	parser,
	"Bitwise Operations Loop",
	"Repeated AND/OR/XOR/SHIFT in a loop to stress ALU-heavy dispatch.",
	<<~ASM
		.int 1000
		FUNC main 0 4
		ILDC 0
		VSTORE 0
		BIPUSH 0
		VSTORE 1
		BIPUSH 1
		VSTORE 2
		loop:
		VLOAD 1
		VLOAD 0
		IF_ICMPGE end
		VLOAD 2
		VLOAD 1
		IXOR
		VLOAD 2
		VLOAD 1
		IAND
		IADD
		VLOAD 2
		VLOAD 1
		IOR
		IADD
		VSTORE 3
		VLOAD 3
		VLOAD 3
		BIPUSH 1
		ISHL
		IXOR
		VSTORE 2
		VLOAD 1
		BIPUSH 1
		IADD
		VSTORE 1
		GOTO loop
		end:
		VLOAD 2
		RETURN
		END
	ASM
)

seed_program(
	parser,
	"Pointer Arithmetic Test",
	"Allocates a block and uses pointer offsets to store and sum integers.",
	<<~ASM
		FUNC main 0 2
		NEW 16
		VSTORE 0
		VLOAD 0
		BIPUSH 10
		IMSTORE
		VLOAD 0
		AADDF 4
		BIPUSH 20
		IMSTORE
		VLOAD 0
		AADDF 8
		BIPUSH 30
		IMSTORE
		VLOAD 0
		AADDF 12
		BIPUSH 40
		IMSTORE
		BIPUSH 0
		VSTORE 1
		VLOAD 0
		IMLOAD
		VLOAD 1
		IADD
		VSTORE 1
		VLOAD 0
		AADDF 4
		IMLOAD
		VLOAD 1
		IADD
		VSTORE 1
		VLOAD 0
		AADDF 8
		IMLOAD
		VLOAD 1
		IADD
		VSTORE 1
		VLOAD 0
		AADDF 12
		IMLOAD
		VLOAD 1
		IADD
		VSTORE 1
		VLOAD 1
		RETURN
		END
	ASM
)

seed_program(
	parser,
	"Loop With Function Calls",
	"Calls a helper function each iteration to measure call-frame overhead.",
	<<~ASM
		.int 500
		FUNC main 0 3
		ILDC 0
		VSTORE 0
		BIPUSH 0
		VSTORE 1
		BIPUSH 0
		VSTORE 2
		loop:
		VLOAD 1
		VLOAD 0
		IF_ICMPGE end
		VLOAD 2
		INVOKESTATIC 1
		VSTORE 2
		VLOAD 1
		BIPUSH 1
		IADD
		VSTORE 1
		GOTO loop
		end:
		VLOAD 2
		RETURN
		END
		FUNC inc 1 0
		VLOAD 0
		BIPUSH 1
		IADD
		RETURN
		END
	ASM
)

seed_program(
	parser,
	"Mixed Workload Benchmark",
	"Combines array traversal, branches, and arithmetic to emulate realistic workloads.",
	<<~ASM
		.int 100
		FUNC main 0 5
		ILDC 0
		VSTORE 0
		VLOAD 0
		NEWARRAY 4
		VSTORE 1
		BIPUSH 0
		VSTORE 2
		BIPUSH 0
		VSTORE 3
		fill:
		VLOAD 2
		VLOAD 0
		IF_ICMPGE fill_done
		VLOAD 1
		VLOAD 2
		AADDS
		VLOAD 2
		BIPUSH 2
		IMUL
		IMSTORE
		VLOAD 2
		BIPUSH 1
		IADD
		VSTORE 2
		GOTO fill
		fill_done:
		BIPUSH 0
		VSTORE 2
		loop:
		VLOAD 2
		VLOAD 0
		IF_ICMPGE end
		VLOAD 2
		BIPUSH 2
		IREM
		VSTORE 4
		VLOAD 3
		VLOAD 1
		VLOAD 2
		AADDS
		IMLOAD
		VLOAD 4
		BIPUSH 0
		IF_CMPEQ even
		IADD
		VSTORE 3
		GOTO after
		even:
		ISUB
		VSTORE 3
		after:
		VLOAD 2
		BIPUSH 1
		IADD
		VSTORE 2
		GOTO loop
		end:
		VLOAD 3
		RETURN
		END
	ASM
)
# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
