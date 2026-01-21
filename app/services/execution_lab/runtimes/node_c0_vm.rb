require "json"
require "open3"

module ExecutionLab
  module Runtimes
    class NodeC0VM
      include ExecutionLab::RuntimeInterface

      def initialize(runtime: nil)
        @runtime = runtime
      end

      def run(program, record_trace: false)
        script = File.expand_path("node_c0_vm.js", __dir__)
        input = { program: program, record_trace: record_trace }

        stdout, stderr, status = Open3.capture3(
          "node",
          script,
          stdin_data: JSON.dump(input)
        )

        raise ExecutionLab::VMError, stderr.presence || "Node runtime failed" unless status.success?

        payload = JSON.parse(stdout)
        {
          result: payload.fetch("result"),
          metrics: payload.fetch("metrics"),
          trace: payload["trace"]
        }
      rescue JSON::ParserError => e
        raise ExecutionLab::VMError, "Node runtime returned invalid JSON: #{e.message}"
      end
    end
  end
end
