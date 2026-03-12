class ProgramsController < ApplicationController
  before_action :set_program, only: %i[ show edit update destroy compare ]

  # GET /programs or /programs.json
  def index
    @programs = Program.order(:name)
  end

  # GET /programs/1 or /programs/1.json
  def show
  end

  # GET /programs/new
  def new
    @program = Program.new
  end

  # GET /programs/1/edit
  def edit
  end

  # POST /programs or /programs.json
  def create
    @program = Program.new(normalized_program_params)
    apply_assembly_source(@program)

    respond_to do |format|
      if @program.save
        format.html { redirect_to @program, notice: "Program was successfully created." }
        format.json { render :show, status: :created, location: @program }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @program.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /programs/1 or /programs/1.json
  def update
    respond_to do |format|
      @program.assign_attributes(normalized_program_params)
      apply_assembly_source(@program)

      if @program.save
        format.html { redirect_to @program, notice: "Program was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @program }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @program.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /programs/1/compare
  def compare
    @runtimes = Runtime.where(instruction_set: @program.instruction_set).order(:name)
    @executions = @runtimes.map do |runtime|
      ExecutionLab::ExecutionEngine.new(program: @program, runtime: runtime, record_trace: false).run
    rescue ExecutionLab::VMError => e
      Execution.new(program: @program, runtime: runtime, status: :failed, error: e.message)
    end
  end

  # DELETE /programs/1 or /programs/1.json
  def destroy
    @program.destroy!

    respond_to do |format|
      format.html { redirect_to programs_path, notice: "Program was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_program
      @program = Program.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def program_params
      params.expect(program: [ :name, :description, :instruction_set, :bytecode, :assembly_source ])
    end

    def normalized_program_params
      attrs = program_params
      return attrs unless attrs[:bytecode].is_a?(String)

      begin
        attrs[:bytecode] = JSON.parse(attrs[:bytecode])
      rescue JSON::ParserError
        # keep original string to trigger validation error
      end

      attrs
    end

    def apply_assembly_source(program)
      source = program_params[:assembly_source]
      return if source.blank?

      program.assembly_source = source
      parser = ExecutionLab::BytecodeParser.new
      program.bytecode = parser.parse(source)
      program.instruction_set = "c0-vm" if program.instruction_set.blank?
    rescue ArgumentError => e
      program.errors.add(:bytecode, e.message)
    end
end
