module ExecutionLab
  class ExecutionEngine
    def initialize(program:, runtime:, record_trace: false)
      @program = program
      @runtime = runtime
      @record_trace = record_trace
    end

    def run
      validate_instruction_set!

      execution = Execution.create!(
        program: @program,
        runtime: @runtime,
        status: :running
      )

      adapter = build_adapter
      result = adapter.run(@program.bytecode, record_trace: @record_trace)

      execution.update!(
        status: :completed,
        result: result.fetch(:result),
        metrics: result.fetch(:metrics)
      )

      persist_traces(execution, result[:trace]) if @record_trace && result[:trace].is_a?(Array)

      execution
    rescue ExecutionLab::VMError => e
      execution&.update!(status: :failed, error: e.message)
      raise
    rescue StandardError => e
      execution&.update!(status: :failed, error: "Unexpected error: #{e.message}")
      raise
    end

    private

    def validate_instruction_set!
      return if @program.instruction_set == @runtime.instruction_set

      raise ExecutionLab::VMError,
            "Instruction set mismatch: program #{@program.instruction_set} vs runtime #{@runtime.instruction_set}"
    end

    def build_adapter
      klass = @runtime.adapter_class.constantize
      klass.new(runtime: @runtime)
    end

    def persist_traces(execution, trace)
      trace.each_with_index do |entry, index|
        execution.execution_traces.create!(
          step: index,
          pc: entry.fetch(:pc),
          opcode: entry.fetch(:opcode),
          snapshot: entry
        )
      end
    end
  end
end
