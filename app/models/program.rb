class Program < ApplicationRecord
	attr_accessor :assembly_source
	VALID_OPCODES = %w[
		POP DUP SWAP
		IADD ISUB IMUL IDIV IREM IAND IOR IXOR ISHL ISHR
		BIPUSH ILDC ALDC ACONST_NULL
		VLOAD VSTORE
		NOP GOTO IF_CMPEQ IF_CMPNE IF_ICMPLT IF_ICMPLE IF_ICMPGT IF_ICMPGE
		ASSERT ATHROW
		INVOKESTATIC INVOKENATIVE RETURN
		NEW IMLOAD IMSTORE AMLOAD AMSTORE CMLOAD CMSTORE AADDF
		NEWARRAY ARRAYLENGTH AADDS
		CHECKTAG HASTAG ADDTAG ADDROF_STATIC ADDROF_NATIVE INVOKEDYNAMIC
	].freeze

	OPCODE_SIZES = {
		"BIPUSH" => 2,
		"ILDC" => 3,
		"ALDC" => 3,
		"VLOAD" => 2,
		"VSTORE" => 2,
		"GOTO" => 3,
		"IF_CMPEQ" => 3,
		"IF_CMPNE" => 3,
		"IF_ICMPLT" => 3,
		"IF_ICMPLE" => 3,
		"IF_ICMPGT" => 3,
		"IF_ICMPGE" => 3,
		"INVOKESTATIC" => 3,
		"INVOKENATIVE" => 3,
		"NEW" => 2,
		"AADDF" => 2,
		"NEWARRAY" => 2
	}.freeze

	validates :name, presence: true
	validates :instruction_set, presence: true
	validates :bytecode, presence: true
	validate :validate_bytecode_structure

	private

	def validate_bytecode_structure
		return if bytecode.blank?

		if bytecode.is_a?(Array)
			validate_instructions(bytecode, "bytecode")
			return
		end

		unless bytecode.is_a?(Hash)
			errors.add(:bytecode, "must be an array of instructions or a structured hash")
			return
		end

		functions = bytecode["functions"] || bytecode[:functions]
		unless functions.is_a?(Array) && functions.any?
			errors.add(:bytecode, "must include functions")
			return
		end

		functions.each_with_index do |fn, index|
			code = fn["code"] || fn[:code]
			if !code.is_a?(Array) || code.empty?
				errors.add(:bytecode, "function #{index} must include code")
				next
			end
			validate_instructions(code, "bytecode.functions[#{index}].code")

			num_args = fn["num_args"] || fn[:num_args]
			num_vars = fn["num_vars"] || fn[:num_vars]
			errors.add(:bytecode, "function #{index} num_args must be an integer") unless num_args.is_a?(Integer)
			errors.add(:bytecode, "function #{index} num_vars must be an integer") unless num_vars.is_a?(Integer)
		end
	end

	def validate_instructions(instructions, path)
		expected_pc = 0

		instructions.each_with_index do |ins, idx|
			unless ins.is_a?(Hash)
				errors.add(:bytecode, "#{path}[#{idx}] must be an object")
				next
			end

			opcode = ins["opcode"] || ins[:opcode]
			pc = ins["pc"] || ins[:pc]
			operand = ins["operand"] || ins[:operand]

			unless VALID_OPCODES.include?(opcode)
				errors.add(:bytecode, "#{path}[#{idx}] has invalid opcode")
				next
			end

			unless pc.is_a?(Integer)
				errors.add(:bytecode, "#{path}[#{idx}] pc must be an integer")
			end

			size = OPCODE_SIZES.fetch(opcode, 1)
			if pc.is_a?(Integer) && pc != expected_pc
				errors.add(:bytecode, "#{path}[#{idx}] pc expected #{expected_pc}")
			end
			expected_pc += size

			if size > 1 && operand.nil?
				errors.add(:bytecode, "#{path}[#{idx}] operand is required")
			end

			validate_operand(opcode, operand, "#{path}[#{idx}]") if size > 1
		end
	end

	def validate_operand(opcode, operand, path)
		unless operand.is_a?(Integer)
			errors.add(:bytecode, "#{path} operand must be an integer")
			return
		end

		case opcode
		when "BIPUSH"
			errors.add(:bytecode, "#{path} operand out of range") unless operand.between?(-128, 127)
		when "ILDC", "ALDC", "INVOKESTATIC", "INVOKENATIVE"
			errors.add(:bytecode, "#{path} operand out of range") unless operand.between?(0, 65_535)
		when "VLOAD", "VSTORE", "NEW", "NEWARRAY", "AADDF"
			errors.add(:bytecode, "#{path} operand out of range") unless operand.between?(0, 255)
		when "GOTO", "IF_CMPEQ", "IF_CMPNE", "IF_ICMPLT", "IF_ICMPLE", "IF_ICMPGT", "IF_ICMPGE"
			errors.add(:bytecode, "#{path} operand out of range") unless operand.between?(-32_768, 32_767)
		end
	end
end
