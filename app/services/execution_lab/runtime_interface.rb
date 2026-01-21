module ExecutionLab
  module RuntimeInterface
    def run(_program, record_trace: false)
      raise NotImplementedError, "runtime must implement run"
    end

    def step
      raise NotImplementedError, "runtime must implement step"
    end

    def state
      raise NotImplementedError, "runtime must implement state"
    end

    def metrics
      raise NotImplementedError, "runtime must implement metrics"
    end
  end
end
