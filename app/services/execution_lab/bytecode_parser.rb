module ExecutionLab
  class BytecodeParser
    Instruction = Struct.new(:pc, :opcode, :operand, keyword_init: true)

    OPCODE_SIZES = Program::OPCODE_SIZES

    def parse(text)
      raise ArgumentError, "text is required" if text.blank?

      lines = text.lines
      functions = []
      current = nil
      labels = {}
      unresolved = []
      int_pool = []
      string_pool = []
      native_pool = []

      pc = 0

      lines.each_with_index do |line, line_index|
        stripped = strip_comment(line).strip
        next if stripped.empty?

        if stripped.start_with?(".int ")
          int_pool << Integer(stripped.split(" ", 2).last)
          next
        end

        if stripped.start_with?(".string ")
          value = stripped.split(" ", 2).last
          string_pool << value.delete_prefix('"').delete_suffix('"')
          next
        end

        if stripped.start_with?(".native ")
          parts = stripped.split(" ")
          native_pool << { "num_args" => Integer(parts[1]), "function_table_index" => Integer(parts[2]) }
          next
        end

        if stripped.start_with?("FUNC ")
          parts = stripped.split(" ")
          current = {
            "name" => parts[1],
            "num_args" => Integer(parts[2]),
            "num_vars" => Integer(parts[3]),
            "code" => []
          }
          pc = 0
          labels = {}
          unresolved = []
          next
        end

        if stripped == "END"
          resolve_labels!(current, labels, unresolved)
          functions << current if current
          current = nil
          next
        end

        if stripped.end_with?(":")
          label = stripped.delete_suffix(":")
          labels[label] = pc
          next
        end

        ensure_function!(current, line_index)

        opcode, operand = parse_instruction(stripped)
        ins = { "pc" => pc, "opcode" => opcode, "operand" => operand }
        current["code"] << ins

        if operand.is_a?(String)
          unresolved << { label: operand, pc: pc, opcode: opcode }
        end

        pc += instruction_size(opcode)
      end

      resolve_labels!(current, labels, unresolved) if current
      functions << current if current

      {
        "instruction_set" => "c0-vm",
        "int_pool" => int_pool,
        "string_pool" => string_pool,
        "native_pool" => native_pool,
        "functions" => functions
      }
    end

    private

    def parse_instruction(line)
      parts = line.split(" ")
      opcode = parts.first
      operand = parts[1]
      return [opcode, nil] if operand.nil?

      if label_operand?(operand)
        [opcode, operand]
      else
        [opcode, Integer(operand)]
      end
    end

    def instruction_size(opcode)
      OPCODE_SIZES.fetch(opcode, 1)
    end

    def label_operand?(operand)
      operand.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
    end

    def strip_comment(line)
      line.split(";", 2).first
    end

    def resolve_labels!(function, labels, unresolved)
      return if function.nil?

      unresolved.each do |entry|
        label_pc = labels[entry[:label]]
        raise ArgumentError, "Unknown label #{entry[:label]}" if label_pc.nil?

        target_pc = label_pc
        offset = target_pc - entry[:pc]

        function["code"].each do |ins|
          ins_pc = ins["pc"] || ins[:pc]
          ins_op = ins["opcode"] || ins[:opcode]
          next unless ins_pc == entry[:pc] && ins_op == entry[:opcode]

          ins["operand"] = offset
          ins[:operand] = offset
        end
      end
    end

    def ensure_function!(current, line_index)
      return if current

      raise ArgumentError, "Instruction outside function on line #{line_index + 1}"
    end
  end
end
