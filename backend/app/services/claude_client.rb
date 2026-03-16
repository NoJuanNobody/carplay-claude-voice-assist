# frozen_string_literal: true

class ClaudeClient
  class ApiError < StandardError; end
  class RateLimitError < ApiError; end
  class TimeoutError < ApiError; end

  API_URL = "https://api.anthropic.com/v1/messages"
  API_VERSION = "2023-06-01"
  MAX_RETRIES = 3
  TIMEOUT_SECONDS = 30

  TOOL_DEFINITIONS = [
    {
      name: "navigate_to",
      description: "Navigate to a destination using the vehicle's navigation system.",
      input_schema: {
        type: "object",
        properties: {
          destination: { type: "string", description: "The destination address or place name" },
          avoid_highways: { type: "boolean", description: "Whether to avoid highways", default: false },
          avoid_tolls: { type: "boolean", description: "Whether to avoid toll roads", default: false }
        },
        required: ["destination"]
      }
    },
    {
      name: "send_message",
      description: "Send a text message to a contact.",
      input_schema: {
        type: "object",
        properties: {
          contact: { type: "string", description: "The contact name or phone number" },
          message: { type: "string", description: "The message text to send" },
          service: { type: "string", enum: %w[sms imessage whatsapp], description: "The messaging service to use", default: "sms" }
        },
        required: %w[contact message]
      }
    },
    {
      name: "read_messages",
      description: "Read recent messages from a contact or all unread messages.",
      input_schema: {
        type: "object",
        properties: {
          contact: { type: "string", description: "The contact name to filter messages from" },
          unread_only: { type: "boolean", description: "Whether to only return unread messages", default: true },
          limit: { type: "integer", description: "Maximum number of messages to return", default: 5 }
        },
        required: []
      }
    },
    {
      name: "get_calendar_events",
      description: "Retrieve upcoming calendar events.",
      input_schema: {
        type: "object",
        properties: {
          date: { type: "string", description: "The date to check (ISO 8601 format, e.g. 2024-01-15)" },
          limit: { type: "integer", description: "Maximum number of events to return", default: 5 },
          calendar_name: { type: "string", description: "Specific calendar to check" }
        },
        required: []
      }
    },
    {
      name: "play_music",
      description: "Play music from the connected music service.",
      input_schema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Song, artist, album, or playlist name to play" },
          action: { type: "string", enum: %w[play pause skip previous volume_up volume_down], description: "The playback action" },
          source: { type: "string", enum: %w[spotify apple_music local], description: "The music source", default: "spotify" }
        },
        required: ["action"]
      }
    },
    {
      name: "get_weather",
      description: "Get current weather or forecast for a location.",
      input_schema: {
        type: "object",
        properties: {
          location: { type: "string", description: "The location to get weather for (defaults to current location)" },
          forecast: { type: "boolean", description: "Whether to include forecast", default: false }
        },
        required: []
      }
    },
    {
      name: "set_reminder",
      description: "Set a reminder for the user.",
      input_schema: {
        type: "object",
        properties: {
          text: { type: "string", description: "The reminder text" },
          time: { type: "string", description: "When to trigger the reminder (ISO 8601 datetime or relative like 'in 30 minutes')" },
          location: { type: "string", description: "Location-based trigger for the reminder" }
        },
        required: ["text"]
      }
    },
    {
      name: "get_vehicle_status",
      description: "Get current vehicle status information.",
      input_schema: {
        type: "object",
        properties: {
          info_type: { type: "string", enum: %w[fuel battery range tire_pressure oil mileage all], description: "The type of vehicle information to retrieve", default: "all" }
        },
        required: []
      }
    }
  ].freeze

  def initialize(api_key: nil)
    @api_key = api_key || ENV.fetch("ANTHROPIC_API_KEY")
    @connection = build_connection
  end

  def chat(messages:, system: nil, tools: nil, max_tokens: 1024, model: "claude-sonnet-4-20250514")
    body = {
      model: model,
      max_tokens: max_tokens,
      messages: messages
    }
    body[:system] = system if system
    body[:tools] = tools if tools

    response = execute_with_retries(body)
    parse_response(response)
  end

  def chat_with_tools(messages:, system: nil, tools: nil, max_tokens: 1024)
    tools ||= TOOL_DEFINITIONS
    result = chat(messages: messages, system: system, tools: tools, max_tokens: max_tokens)

    if result[:tool_calls]&.any?
      result[:requires_tool_execution] = true
    end

    result
  end

  private

  def build_connection
    Faraday.new(url: API_URL) do |f|
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = 10
      f.headers["Content-Type"] = "application/json"
      f.headers["x-api-key"] = @api_key
      f.headers["anthropic-version"] = API_VERSION
      f.adapter Faraday.default_adapter
    end
  end

  def execute_with_retries(body)
    retries = 0
    begin
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @connection.post do |req|
        req.body = JSON.generate(body)
      end

      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

      log_metrics(body[:model], response.status, elapsed_ms)

      handle_error_response(response) unless response.status == 200

      response
    rescue Faraday::TimeoutError => e
      retries += 1
      raise TimeoutError, "Request timed out after #{TIMEOUT_SECONDS}s" if retries > MAX_RETRIES

      sleep_with_backoff(retries)
      retry
    rescue RateLimitError => e
      retries += 1
      raise if retries > MAX_RETRIES

      sleep_with_backoff(retries)
      retry
    rescue Faraday::ConnectionFailed => e
      retries += 1
      raise ApiError, "Connection failed: #{e.message}" if retries > MAX_RETRIES

      sleep_with_backoff(retries)
      retry
    end
  end

  def handle_error_response(response)
    body = JSON.parse(response.body) rescue {}
    error_message = body.dig("error", "message") || "Unknown API error"

    case response.status
    when 429
      raise RateLimitError, "Rate limited: #{error_message}"
    when 400..499
      raise ApiError, "Client error (#{response.status}): #{error_message}"
    when 500..599
      raise ApiError, "Server error (#{response.status}): #{error_message}"
    else
      raise ApiError, "Unexpected status (#{response.status}): #{error_message}"
    end
  end

  def parse_response(response)
    body = JSON.parse(response.body)

    content_blocks = body["content"] || []
    text_content = content_blocks
      .select { |block| block["type"] == "text" }
      .map { |block| block["text"] }
      .join("\n")

    tool_calls = content_blocks
      .select { |block| block["type"] == "tool_use" }
      .map do |block|
        {
          id: block["id"],
          name: block["name"],
          input: block["input"]
        }
      end

    usage = body["usage"] || {}

    {
      role: body["role"] || "assistant",
      content: text_content,
      tool_calls: tool_calls.any? ? tool_calls : nil,
      stop_reason: body["stop_reason"],
      usage: {
        input_tokens: usage["input_tokens"] || 0,
        output_tokens: usage["output_tokens"] || 0
      }
    }
  end

  def sleep_with_backoff(retry_count)
    sleep_time = (2**retry_count) + rand(0.0..0.5)
    sleep(sleep_time)
  end

  def log_metrics(model, status, elapsed_ms)
    Rails.logger.info(
      "[ClaudeClient] model=#{model} status=#{status} latency_ms=#{elapsed_ms}"
    )
  end
end
