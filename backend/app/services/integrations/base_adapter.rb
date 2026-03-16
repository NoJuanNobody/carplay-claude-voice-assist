# frozen_string_literal: true

module Integrations
  class BaseAdapter
    class AdapterError < StandardError; end
    class ValidationError < AdapterError; end
    class TimeoutError < AdapterError; end
    class NotImplementedError < AdapterError; end

    DEFAULT_TIMEOUT = 10 # seconds

    Result = Struct.new(:success, :data, :error, keyword_init: true) do
      def to_h
        { success: success, data: data || {}, error: error }
      end
    end

    def initialize(timeout: nil)
      @timeout = timeout || self.class::DEFAULT_TIMEOUT
    end

    def execute(input, user:)
      raise NotImplementedError, "#{self.class.name} must implement #execute"
    end

    protected

    def success_result(data = {})
      Result.new(success: true, data: data, error: nil)
    end

    def error_result(message, data = {})
      Result.new(success: false, data: data, error: message)
    end

    def with_timeout(&block)
      Timeout.timeout(@timeout) { yield }
    rescue ::Timeout::Error
      raise TimeoutError, "#{self.class.name} timed out after #{@timeout}s"
    end

    def validate_required!(input, *keys)
      missing = keys.select { |k| input[k.to_s].blank? && input[k.to_sym].blank? }
      if missing.any?
        raise ValidationError, "Missing required fields: #{missing.join(', ')}"
      end
    end

    def fetch_input(input, key, default = nil)
      input[key.to_s] || input[key.to_sym] || default
    end

    def log_execution(action, details = {})
      Rails.logger.info(
        "[#{self.class.name}] action=#{action} #{details.map { |k, v| "#{k}=#{v}" }.join(' ')}"
      )
    end
  end
end
