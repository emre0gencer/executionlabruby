class ExecutionsController < ApplicationController
  before_action :set_execution, only: %i[show]

  def index
    @executions = Execution.order(created_at: :desc).includes(:program, :runtime)
  end

  def new
    @program = Program.find(params.expect(:program_id)) if params[:program_id].present?
    @programs = Program.order(:name)
    @runtimes = Runtime.order(:name)
  end

  def create
    program = Program.find(params.expect(:program_id))
    runtime = Runtime.find(params.expect(:runtime_id))
    record_trace = params[:record_trace] == "1"

    engine = ExecutionLab::ExecutionEngine.new(
      program: program,
      runtime: runtime,
      record_trace: record_trace
    )

    execution = engine.run

    redirect_to execution_path(execution), notice: "Execution completed."
  rescue ExecutionLab::VMError => e
    redirect_to program_path(program), alert: e.message
  end

  def show
  end

  private

  def set_execution
    @execution = Execution.find(params.expect(:id))
  end
end
