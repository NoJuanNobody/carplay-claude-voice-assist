# frozen_string_literal: true

require "singleton"

module Metrics
  class Collector
    include Singleton

    def initialize
      @mutex = Mutex.new
      reset!
    end

    def record_request(path, method, status, duration_ms)
      @mutex.synchronize do
        @requests_total += 1
        @response_times << duration_ms
        @status_counts[status] = (@status_counts[status] || 0) + 1

        if status >= 400
          @errors_total += 1
        end
      end
    end

    def record_error(type, message)
      @mutex.synchronize do
        @errors_total += 1
        @recent_errors << {
          type: type,
          message: message,
          timestamp: Time.current.iso8601
        }
        @recent_errors.shift if @recent_errors.size > 100
      end
    end

    def record_session_event(type)
      @mutex.synchronize do
        case type.to_sym
        when :start
          @active_sessions += 1
        when :end
          @active_sessions = [@active_sessions - 1, 0].max
        end
      end
    end

    def snapshot
      @mutex.synchronize do
        avg_response = if @response_times.any?
          (@response_times.sum.to_f / @response_times.size).round(2)
        else
          0.0
        end

        error_rate = if @requests_total > 0
          (@errors_total.to_f / @requests_total * 100).round(2)
        else
          0.0
        end

        {
          requests_total: @requests_total,
          errors_total: @errors_total,
          avg_response_ms: avg_response,
          error_rate: error_rate,
          active_sessions: @active_sessions,
          status_counts: @status_counts.dup,
          recent_errors: @recent_errors.dup,
          uptime_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at).round
        }
      end
    end

    def reset!
      @mutex ||= Mutex.new
      @mutex.synchronize do
        @requests_total = 0
        @errors_total = 0
        @response_times = []
        @status_counts = {}
        @active_sessions = 0
        @recent_errors = []
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
