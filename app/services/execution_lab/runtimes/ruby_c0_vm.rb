require "json"

module ExecutionLab
  module Runtimes
    class RubyC0VM
      include ExecutionLab::RuntimeInterface

      Frame = Struct.new(:stack, :code, :pc, :locals, keyword_init: true)

      C0Value = Struct.new(:kind, :value, keyword_init: true) do
        def self.int(value)
          new(kind: :int, value: value)
        end

        def self.ptr(value)
          new(kind: :ptr, value: value)
        end
      end

      class Pointer
        attr_reader :block, :offset

        def initialize(block, offset = 0)
          @block = block
          @offset = offset
        end
      end

      class TaggedPointer
        attr_reader :ptr, :tag

        def initialize(ptr, tag)
          @ptr = ptr
          @tag = tag
        end
      end

      class FunPtr
        attr_reader :index, :native

        def initialize(index, native)
          @index = index
          @native = native
        end
      end

      class MemoryBlock
        attr_reader :size, :bytes, :ptr_slots

        def initialize(size)
          @size = size
          @bytes = Array.new(size, 0)
          @ptr_slots = {}
        end

        def read_int32(offset)
          b0 = bytes.fetch(offset, 0)
          b1 = bytes.fetch(offset + 1, 0)
          b2 = bytes.fetch(offset + 2, 0)
          b3 = bytes.fetch(offset + 3, 0)
          value = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
          to_int32(value)
        end

        def write_int32(offset, value)
          v = value & 0xFFFFFFFF
          bytes[offset] = v & 0xFF
          bytes[offset + 1] = (v >> 8) & 0xFF
          bytes[offset + 2] = (v >> 16) & 0xFF
          bytes[offset + 3] = (v >> 24) & 0xFF
        end

        def read_byte(offset)
          bytes.fetch(offset, 0)
        end

        def write_byte(offset, value)
          bytes[offset] = value & 0xFF
        end

        def read_ptr(offset)
          ptr_slots[offset]
        end

        def write_ptr(offset, value)
          ptr_slots[offset] = value
        end

        def to_string(offset = 0)
          result = []
          idx = offset
          loop do
            byte = bytes[idx]
            break if byte.nil? || byte == 0

            result << byte
            idx += 1
          end
          result.pack("C*")
        end

        private

        def to_int32(value)
          value = value & 0xFFFFFFFF
          value >= 0x80000000 ? value - 0x100000000 : value
        end
      end

      class ArrayObject
        attr_reader :count, :elt_size, :elems

        def initialize(count, elt_size)
          @count = count
          @elt_size = elt_size
          @elems = MemoryBlock.new(count * elt_size)
        end
      end

      OPCODE_SIZES = Program::OPCODE_SIZES

      def initialize(runtime: nil, native_registry: {})
        @runtime = runtime
        @native_registry = native_registry
        reset_runtime_state
      end

      def run(program, record_trace: false)
        load_program(program)
        @record_trace = record_trace
        @trace = []

        @status = :running
        @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        while @status == :running
          step
        end

        @end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        {
          result: @result,
          metrics: metrics,
          trace: @trace
        }
      end

      def step
        raise ExecutionLab::VMError, "runtime not loaded" if @code.nil?
        return if @status != :running

        ins = fetch_instruction(@pc)
        opcode = ins.fetch(:opcode)
        operand = ins[:operand]

        record_trace(opcode, operand)

        @instruction_count += 1

        case opcode
        when "POP"
          @pc += 1
          pop
        when "DUP"
          @pc += 1
          v = pop
          push(v)
          push(v)
        when "SWAP"
          @pc += 1
          v2 = pop
          v1 = pop
          push(v2)
          push(v1)
        when "RETURN"
          handle_return
        when "IADD"
          @pc += 1
          y = val2int(pop)
          x = val2int(pop)
          push(C0Value.int(to_int32(x + y)))
        when "ISUB"
          @pc += 1
          y = val2int(pop)
          x = val2int(pop)
          push(C0Value.int(to_int32(x - y)))
        when "IMUL"
          @pc += 1
          y = val2int(pop)
          x = val2int(pop)
          push(C0Value.int(to_int32(x * y)))
        when "IDIV"
          @pc += 1
          y = val2int(pop)
          x = val2int(pop)
          raise ExecutionLab::ArithmeticError, "Division by zero" if y == 0

          push(C0Value.int(to_int32(div_toward_zero(x, y))))
        when "IREM"
          @pc += 1
          y = val2int(pop)
          x = val2int(pop)
          raise ExecutionLab::ArithmeticError, "Remainder by zero" if y == 0

          q = div_toward_zero(x, y)
          push(C0Value.int(to_int32(x - (q * y))))
        when "IAND"
          @pc += 1
          y = val2int(pop)
          x = val2int(pop)
          push(C0Value.int(to_int32(x & y)))
        when "IOR"
          @pc += 1
          y = val2int(pop)
          x = val2int(pop)
          push(C0Value.int(to_int32(x | y)))
        when "IXOR"
          @pc += 1
          y = val2int(pop)
          x = val2int(pop)
          push(C0Value.int(to_int32(x ^ y)))
        when "ISHR"
          @pc += 1
          y = val2int(pop)
          x = val2int(pop)
          raise ExecutionLab::ArithmeticError, "Shift out of range" if y < 0 || y >= 32

          push(C0Value.int(to_int32(x >> y)))
        when "ISHL"
          @pc += 1
          y = val2int(pop)
          x = val2int(pop)
          raise ExecutionLab::ArithmeticError, "Shift out of range" if y < 0 || y >= 32

          push(C0Value.int(to_int32(x << y)))
        when "BIPUSH"
          x = sign8(operand)
          push(C0Value.int(x))
          @pc += 2
        when "ILDC"
          index = operand
          value = @int_pool.fetch(index)
          push(C0Value.int(to_int32(value)))
          @pc += 3
        when "ALDC"
          index = operand
          ptr = @string_pool.fetch(index)
          push(C0Value.ptr(ptr))
          @pc += 3
        when "ACONST_NULL"
          push(C0Value.ptr(nil))
          @pc += 1
        when "VLOAD"
          idx = operand
          check_local_index!(idx)
          push(@locals[idx])
          @pc += 2
        when "VSTORE"
          idx = operand
          check_local_index!(idx)
          @locals[idx] = pop
          @pc += 2
        when "ATHROW"
          msg_ptr = val2ptr(pop)
          raise ExecutionLab::UserError, ptr_to_string(msg_ptr)
        when "ASSERT"
          msg_ptr = val2ptr(pop)
          value = val2int(pop)
          raise ExecutionLab::AssertionFailure, ptr_to_string(msg_ptr) if value == 0

          @pc += 1
        when "NOP"
          @pc += 1
        when "IF_CMPEQ"
          handle_if_cmp { |v1, v2| val_equal(v1, v2) }
        when "IF_CMPNE"
          handle_if_cmp { |v1, v2| !val_equal(v1, v2) }
        when "IF_ICMPLT"
          handle_if_icmp { |x, y| x < y }
        when "IF_ICMPGE"
          handle_if_icmp { |x, y| x >= y }
        when "IF_ICMPGT"
          handle_if_icmp { |x, y| x > y }
        when "IF_ICMPLE"
          handle_if_icmp { |x, y| x <= y }
        when "GOTO"
          @pc = @pc + operand
        when "INVOKESTATIC"
          invoke_static(operand)
        when "INVOKENATIVE"
          invoke_native(operand)
        when "NEW"
          ptr = Pointer.new(MemoryBlock.new(operand), 0)
          push(C0Value.ptr(ptr))
          @pc += 2
        when "IMLOAD"
          @pc += 1
          ptr = val2ptr(pop)
          raise ExecutionLab::MemoryError, "imload on NULL" if ptr.nil?

          push(C0Value.int(ptr.block.read_int32(ptr.offset)))
        when "IMSTORE"
          @pc += 1
          value = val2int(pop)
          ptr = val2ptr(pop)
          raise ExecutionLab::MemoryError, "imstore on NULL" if ptr.nil?

          ptr.block.write_int32(ptr.offset, value)
        when "AMLOAD"
          @pc += 1
          ptr = val2ptr(pop)
          raise ExecutionLab::MemoryError, "amload on NULL" if ptr.nil?

          push(C0Value.ptr(ptr.block.read_ptr(ptr.offset)))
        when "AMSTORE"
          @pc += 1
          value = val2ptr(pop)
          ptr = val2ptr(pop)
          raise ExecutionLab::MemoryError, "amstore on NULL" if ptr.nil?

          ptr.block.write_ptr(ptr.offset, value)
        when "CMLOAD"
          @pc += 1
          ptr = val2ptr(pop)
          raise ExecutionLab::MemoryError, "cmload on NULL" if ptr.nil?

          push(C0Value.int(to_int32(ptr.block.read_byte(ptr.offset))))
        when "CMSTORE"
          @pc += 1
          value = val2int(pop)
          ptr = val2ptr(pop)
          raise ExecutionLab::MemoryError, "cmstore on NULL" if ptr.nil?

          ptr.block.write_byte(ptr.offset, value & 0x7F)
        when "AADDF"
          ptr = val2ptr(pop)
          raise ExecutionLab::MemoryError, "aaddf on NULL" if ptr.nil?

          @pc += 2
          push(C0Value.ptr(Pointer.new(ptr.block, ptr.offset + operand)))
        when "NEWARRAY"
          capacity = val2int(pop)
          raise ExecutionLab::MemoryError, "invalid size" if capacity < 0

          @pc += 2
          if capacity == 0
            push(C0Value.ptr(nil))
          else
            array = ArrayObject.new(capacity, operand)
            push(C0Value.ptr(array))
          end
        when "ARRAYLENGTH"
          @pc += 1
          ptr = val2ptr(pop)
          length = ptr.nil? ? 0 : ptr.count
          push(C0Value.int(to_int32(length)))
        when "AADDS"
          @pc += 1
          index = val2int(pop)
          array_ptr = val2ptr(pop)
          raise ExecutionLab::MemoryError, "aadds on NULL array" if array_ptr.nil?

          len = array_ptr.count
          raise ExecutionLab::MemoryError, "array index out of bounds" if index < 0 || index >= len

          offset = index * array_ptr.elt_size
          push(C0Value.ptr(Pointer.new(array_ptr.elems, offset)))
        when "CHECKTAG", "HASTAG", "ADDTAG", "ADDROF_STATIC", "ADDROF_NATIVE", "INVOKEDYNAMIC"
          raise ExecutionLab::InvalidOpcodeError, "unsupported opcode #{opcode}"
        else
          raise ExecutionLab::InvalidOpcodeError, "invalid opcode #{opcode}"
        end

        state
      end

      def state
        {
          status: @status,
          pc: @pc,
          stack_depth: @stack.size,
          locals_count: @locals.size,
          call_depth: @call_stack.size,
          output: @output.dup,
          error: @error
        }
      end

      def metrics
        duration_ms = if @start_time && @end_time
                        ((@end_time - @start_time) * 1000.0).round(3)
                      else
                        0.0
                      end

        {
          instruction_count: @instruction_count,
          execution_time_ms: duration_ms,
          max_stack_depth: @max_stack_depth,
          runtime: "ruby"
        }
      end

      private

      def reset_runtime_state
        @stack = []
        @locals = []
        @call_stack = []
        @pc = 0
        @code = nil
        @functions = []
        @int_pool = []
        @string_pool = []
        @native_pool = []
        @status = :idle
        @result = nil
        @output = []
        @error = nil
        @instruction_count = 0
        @max_stack_depth = 0
        @record_trace = false
        @trace = []
      end

      def load_program(program)
        normalized = normalize_program(program)
        @functions = normalized.fetch(:functions)
        @int_pool = normalized.fetch(:int_pool)
        @string_pool = normalized.fetch(:string_pool)
        @native_pool = normalized.fetch(:native_pool)

        main = @functions.fetch(0)
        @code = main.fetch(:code)
        @pc = 0
        @locals = Array.new(main.fetch(:num_args) + main.fetch(:num_vars)) { C0Value.int(0) }
        @stack = []
        @call_stack = []
      end

      def normalize_program(program)
        data = program.is_a?(String) ? JSON.parse(program) : program
        if data.is_a?(Array)
          return {
            functions: [
              {
                name: "main",
                num_args: 0,
                num_vars: 0,
                code: normalize_code(data)
              }
            ],
            int_pool: [],
            string_pool: [],
            native_pool: []
          }
        end

        functions = Array(data["functions"] || data[:functions]).map do |fn|
          {
            name: fn["name"] || fn[:name],
            num_args: fn["num_args"] || fn[:num_args],
            num_vars: fn["num_vars"] || fn[:num_vars],
            code: normalize_code(fn["code"] || fn[:code])
          }
        end

        strings = Array(data["string_pool"] || data[:string_pool]).map do |str|
          block = MemoryBlock.new(str.bytesize + 1)
          str.bytes.each_with_index { |byte, idx| block.write_byte(idx, byte) }
          block.write_byte(str.bytesize, 0)
          Pointer.new(block, 0)
        end

        {
          functions: functions,
          int_pool: Array(data["int_pool"] || data[:int_pool]),
          string_pool: strings,
          native_pool: Array(data["native_pool"] || data[:native_pool])
        }
      end

      def normalize_code(code)
        Array(code).map do |ins|
          {
            pc: ins["pc"] || ins[:pc],
            opcode: ins["opcode"] || ins[:opcode],
            operand: ins["operand"] || ins[:operand]
          }
        end
      end

      def fetch_instruction(pc)
        ins = @code.find { |i| i[:pc] == pc }
        raise ExecutionLab::InvalidOpcodeError, "no instruction at pc #{pc}" if ins.nil?

        ins
      end

      def push(value)
        @stack << value
        @max_stack_depth = [@max_stack_depth, @stack.size].max
      end

      def pop
        raise ExecutionLab::ValueError, "stack underflow" if @stack.empty?

        @stack.pop
      end

      def val2int(value)
        raise ExecutionLab::ValueError, "Invalid cast from pointer to integer" if value.kind != :int

        value.value
      end

      def val2ptr(value)
        raise ExecutionLab::ValueError, "Invalid cast from integer to pointer" if value.kind != :ptr

        value.value
      end

      def val_equal(v1, v2)
        raise ExecutionLab::ValueError, "val_equal: invalid comparison of an int and a pointer" if v1.kind != v2.kind

        return val2int(v1) == val2int(v2) if v1.kind == :int

        p1 = v1.value
        p2 = v2.value
        return false if (p1.nil? != p2.nil?)
        return true if p1.nil? && p2.nil?

        if tagged_pointer?(p1) && tagged_pointer?(p2)
          return p1.ptr.equal?(p2.ptr)
        end

        if !tagged_pointer?(p1) && !tagged_pointer?(p2)
          if ptr_type(p1) != ptr_type(p2)
            raise ExecutionLab::ValueError,
                  "val_equal: invalid comparison between a function pointer and a regular pointer"
          end
          return p1.equal?(p2)
        end

        raise ExecutionLab::ValueError,
              "val_equal: invalid comparison of a tagged pointer and an untagged pointer"
      end

      def tagged_pointer?(ptr)
        ptr.is_a?(TaggedPointer)
      end

      def ptr_type(ptr)
        return :funptr if ptr.is_a?(FunPtr)
        return :tagged if ptr.is_a?(TaggedPointer)

        :raw
      end

      def handle_if_cmp
        v2 = pop
        v1 = pop
        offset = sign16(fetch_operand)

        if yield(v1, v2)
          @pc = @pc + offset
        else
          @pc += 3
        end
      end

      def handle_if_icmp
        y = val2int(pop)
        x = val2int(pop)
        offset = sign16(fetch_operand)

        if yield(x, y)
          @pc = @pc + offset
        else
          @pc += 3
        end
      end

      def fetch_operand
        ins = fetch_instruction(@pc)
        ins[:operand]
      end

      def invoke_static(index)
        func = @functions.fetch(index)
        return_pc = @pc + 3
        @pc += 3

        num_args = func.fetch(:num_args)
        num_vars = func.fetch(:num_vars)
        locals = Array.new(num_args + num_vars) { C0Value.int(0) }
        (num_args - 1).downto(0) { |i| locals[i] = pop }

        @call_stack << Frame.new(stack: @stack, code: @code, pc: return_pc, locals: @locals)

        @stack = []
        @locals = locals
        @code = func.fetch(:code)
        @pc = 0
      end

      def invoke_native(index)
        native = @native_pool.fetch(index)
        num_args = native.fetch("num_args")
        args = Array.new(num_args)
        (num_args - 1).downto(0) { |i| args[i] = pop }

        fn_index = native.fetch("function_table_index")
        fn = @native_registry[fn_index]
        raise ExecutionLab::UserError, "native function #{fn_index} is not registered" if fn.nil?

        result = fn.call(args)
        push(result)
        @pc += 3
      end

      def handle_return
        retv = pop
        if @call_stack.empty?
          @status = :completed
          @end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @result = { return_value: val2int(retv), output: @output }
          return
        end

        frame = @call_stack.pop
        @stack = frame.stack
        @code = frame.code
        @pc = frame.pc
        @locals = frame.locals
        push(retv)
      end

      def record_trace(opcode, operand)
        return unless @record_trace

        @trace << {
          pc: @pc,
          opcode: opcode,
          operand: operand,
          stack: @stack.map { |v| serialize_value(v) },
          locals: @locals.map { |v| serialize_value(v) }
        }
      end

      def serialize_value(value)
        if value.kind == :int
          { kind: "int", value: value.value }
        else
          { kind: "ptr", value: pointer_label(value.value) }
        end
      end

      def pointer_label(ptr)
        return "NULL" if ptr.nil?
        return "funptr:#{ptr.index}" if ptr.is_a?(FunPtr)
        return "tagged:#{ptr.tag}" if ptr.is_a?(TaggedPointer)
        return "array:#{ptr.object_id}" if ptr.is_a?(ArrayObject)
        return "mem:#{ptr.block.object_id}:#{ptr.offset}" if ptr.is_a?(Pointer)

        "ptr:#{ptr.object_id}"
      end

      def ptr_to_string(ptr)
        return "" if ptr.nil?
        return ptr.to_s if ptr.is_a?(String)
        return ptr.block.to_string(ptr.offset) if ptr.is_a?(Pointer)

        ptr.to_s
      end

      def sign8(value)
        v = value & 0xFF
        v >= 0x80 ? v - 0x100 : v
      end

      def sign16(value)
        v = value & 0xFFFF
        v >= 0x8000 ? v - 0x10000 : v
      end

      def to_int32(value)
        value = value & 0xFFFFFFFF
        value >= 0x80000000 ? value - 0x100000000 : value
      end

      def div_toward_zero(x, y)
        (x.to_f / y).truncate
      end

      def check_local_index!(idx)
        return if idx.between?(0, @locals.length - 1)

        raise ExecutionLab::MemoryError, "invalid local index"
      end
    end
  end
end
