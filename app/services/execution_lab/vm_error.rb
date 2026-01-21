module ExecutionLab
  class VMError < StandardError; end
  class UserError < VMError; end
  class AssertionFailure < VMError; end
  class MemoryError < VMError; end
  class ValueError < VMError; end
  class ArithmeticError < VMError; end
  class InvalidOpcodeError < VMError; end
end
