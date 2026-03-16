# frozen_string_literal: true

module Metrics
  class RequestMiddleware
    SKIPPED_PATHS = %w[/api/v1/health /up].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      path = env["PATH_INFO"]

      if skip_path?(path)
        return @app.call(env)
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status, headers, response = @app.call(env)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

      method = env["REQUEST_METHOD"]
      Metrics::Collector.instance.record_request(path, method, status, duration_ms)

      [status, headers, response]
    rescue StandardError => e
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
      Metrics::Collector.instance.record_request(path, env["REQUEST_METHOD"], 500, duration_ms)
      Metrics::Collector.instance.record_error(e.class.name, e.message)
      raise
    end

    private

    def skip_path?(path)
      SKIPPED_PATHS.any? { |skipped| path.start_with?(skipped) }
    end
  end
end
