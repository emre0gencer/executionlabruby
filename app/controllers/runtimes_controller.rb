class RuntimesController < ApplicationController
  before_action :set_runtime, only: %i[show edit update destroy]

  def index
    @runtimes = Runtime.order(:name)
  end

  def show
  end

  def new
    @runtime = Runtime.new
  end

  def edit
  end

  def create
    @runtime = Runtime.new(normalized_runtime_params)

    if @runtime.save
      redirect_to @runtime, notice: "Runtime was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @runtime.update(normalized_runtime_params)
      redirect_to @runtime, notice: "Runtime was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @runtime.destroy!
    redirect_to runtimes_path, notice: "Runtime was successfully destroyed.", status: :see_other
  end

  private

  def set_runtime
    @runtime = Runtime.find(params.expect(:id))
  end

  def runtime_params
    params.expect(runtime: [ :name, :instruction_set, :adapter_class, :config ])
  end

  def normalized_runtime_params
    attrs = runtime_params
    return attrs unless attrs[:config].is_a?(String)

    begin
      attrs[:config] = JSON.parse(attrs[:config])
    rescue JSON::ParserError
      # keep original string to surface validation errors if needed
    end

    attrs
  end
end
