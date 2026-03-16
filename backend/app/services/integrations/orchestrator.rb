# frozen_string_literal: true

module Integrations
  class Orchestrator
    class UnknownToolError < StandardError; end
    class ToolExecutionError < StandardError; end

    # Registry: maps tool names to their adapter classes and optional action overrides
    TOOL_REGISTRY = {
      "navigate_to"        => { adapter: MapsAdapter },
      "send_message"       => { adapter: MessagesAdapter, action: "send_message" },
      "read_messages"      => { adapter: MessagesAdapter, action: "read_messages" },
      "get_calendar_events" => { adapter: CalendarAdapter, action: "get_calendar_events" },
      "set_reminder"       => { adapter: CalendarAdapter, action: "set_reminder" },
      "play_music"         => { adapter: MediaAdapter },
      "get_weather"        => { adapter: WeatherAdapter },
      "get_vehicle_status" => { adapter: VehicleAdapter }
    }.freeze

    def initialize
      @adapter_cache = {}
    end

    def execute_tool_call(tool_name, input, user:)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      registry_entry = TOOL_REGISTRY[tool_name]

      unless registry_entry
        log_tool_execution(tool_name, nil, false, 0, error: "Unknown tool")
        raise UnknownToolError, "Unknown tool: '#{tool_name}'. Available tools: #{TOOL_REGISTRY.keys.join(', ')}"
      end

      adapter = resolve_adapter(registry_entry[:adapter])

      # Inject the action into the input if the registry specifies one
      enriched_input = input.dup
      if registry_entry[:action]
        enriched_input = enriched_input.merge("action" => registry_entry[:action])
      end

      result = adapter.execute(enriched_input, user: user)

      elapsed_ms = elapsed_since(start_time)
      log_tool_execution(tool_name, registry_entry[:adapter].name, result.success, elapsed_ms)

      result
    rescue BaseAdapter::AdapterError => e
      elapsed_ms = elapsed_since(start_time)
      log_tool_execution(tool_name, registry_entry&.dig(:adapter)&.name, false, elapsed_ms, error: e.message)
      BaseAdapter::Result.new(success: false, data: {}, error: e.message)
    rescue StandardError => e
      elapsed_ms = elapsed_since(start_time)
      log_tool_execution(tool_name, registry_entry&.dig(:adapter)&.name, false, elapsed_ms, error: e.class.name)
      raise ToolExecutionError, "Tool '#{tool_name}' failed: #{e.message}"
    end

    def execute_tool_calls(tool_calls, user:)
      tool_calls.map do |tool_call|
        tool_name = tool_call[:name] || tool_call["name"]
        input = tool_call[:input] || tool_call["input"] || {}
        tool_id = tool_call[:id] || tool_call["id"]

        result = execute_tool_call(tool_name, input, user: user)

        {
          tool_use_id: tool_id,
          tool_name: tool_name,
          result: result.to_h
        }
      end
    end

    def available_tools
      TOOL_REGISTRY.keys
    end

    def tool_registered?(tool_name)
      TOOL_REGISTRY.key?(tool_name)
    end

    private

    def resolve_adapter(adapter_class)
      @adapter_cache[adapter_class] ||= adapter_class.new
    end

    def elapsed_since(start_time)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    end

    def log_tool_execution(tool_name, adapter_name, success, elapsed_ms, error: nil)
      msg = "[Integrations::Orchestrator] tool=#{tool_name} adapter=#{adapter_name} " \
            "success=#{success} latency_ms=#{elapsed_ms}"
      msg += " error=#{error}" if error

      if success
        Rails.logger.info(msg)
      else
        Rails.logger.warn(msg)
      end
    end
  end
end
