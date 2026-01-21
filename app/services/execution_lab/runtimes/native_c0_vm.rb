require "json"
require "open3"

module ExecutionLab
  module Runtimes
    class NativeC0VM
      include ExecutionLab::RuntimeInterface

      def initialize(runtime: nil)
        @runtime = runtime
      end

      def run(program, record_trace: false)
        executable = runtime_config.fetch("executable_path")
        input = { program: program, record_trace: record_trace }

        stdout, stderr, status = Open3.capture3(
          [executable, File.basename(executable)],
          stdin_data: JSON.dump(input)
        )

        raise ExecutionLab::VMError, stderr.presence || "Native C runtime failed" unless status.success?

        payload = JSON.parse(stdout)
        {
          result: payload.fetch("result"),
          metrics: payload.fetch("metrics"),
          trace: payload["trace"]
        }
      rescue KeyError
        raise ExecutionLab::VMError, "Native C runtime missing executable_path config"
      rescue JSON::ParserError => e
        raise ExecutionLab::VMError, "Native C runtime returned invalid JSON: #{e.message}"
      end

      private

      def runtime_config
        @runtime&.config || {}
      end
    end
  end
end
