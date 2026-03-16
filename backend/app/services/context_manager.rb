# frozen_string_literal: true

class ContextManager
  class SessionError < StandardError; end

  DRIVING_STATE_PROMPTS = {
    "parked" => "The user is currently parked. You may provide detailed responses.",
    "driving" => "The user is actively driving. Keep responses extremely brief and safe. " \
                 "Do NOT suggest looking at the screen. Prioritize audio-friendly responses. " \
                 "Avoid any tasks that could distract the driver.",
    "stopped" => "The user is stopped (e.g., at a traffic light). Keep responses concise " \
                 "but you can be slightly more detailed than while driving.",
    "unknown" => "The driving state is unknown. Default to concise, safety-first responses."
  }.freeze

  BASE_SYSTEM_PROMPT = <<~PROMPT
    You are a helpful voice assistant integrated into a car's CarPlay system.
    Your primary goals are:
    1. Keep the driver safe - never encourage distracted driving
    2. Provide concise, clear responses optimized for audio
    3. Use available tools to help with navigation, messaging, music, and vehicle info
    4. Be proactive about safety warnings when appropriate

    Important guidelines:
    - Keep responses short and conversational
    - When reading messages or lists, summarize rather than reading everything verbatim
    - Confirm actions before executing them when safety-critical
    - If a request seems unsafe while driving, suggest waiting until parked
  PROMPT

  attr_reader :user, :session

  def initialize(user:, session: nil)
    @user = user
    @session = session
    @cache = CacheService.new
    @claude = ClaudeClient.new
    @orchestrator = Integrations::Orchestrator.new
  end

  def start_session(vehicle_id: nil)
    vehicle = vehicle_id ? user.vehicles.find(vehicle_id) : nil

    @session = VoiceSession.create!(
      user: user,
      vehicle: vehicle,
      started_at: Time.current,
      driving_state: "unknown",
      metadata: {}
    )

    cache_session_data

    {
      session_id: @session.id,
      session_token: @session.session_token,
      started_at: @session.started_at.iso8601
    }
  end

  def end_session
    raise SessionError, "No active session" unless @session

    @session.update!(ended_at: Time.current)
    @cache.delete("session:#{@session.id}")

    {
      session_id: @session.id,
      ended_at: @session.ended_at.iso8601,
      message_count: @session.conversation_messages.count
    }
  end

  def process_message(text, driving_state: "unknown")
    raise SessionError, "No active session" unless @session
    raise SessionError, "Session has ended" if @session.ended_at.present?

    @session.update!(driving_state: driving_state) if driving_state != @session.driving_state

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    user_message = save_message(role: "user", content: text)

    history = get_conversation_history(limit: 20)
    system_prompt = build_system_prompt(driving_state)
    messages = history.map { |m| { role: m.role, content: m.content } }

    result = @claude.chat_with_tools(
      messages: messages,
      system: system_prompt,
      tools: ClaudeClient::TOOL_DEFINITIONS
    )

    total_tokens = (result[:usage][:input_tokens] || 0) + (result[:usage][:output_tokens] || 0)

    assistant_message = save_message(
      role: "assistant",
      content: result[:content].presence || "",
      tool_calls: result[:tool_calls],
      token_count: total_tokens
    )

    # If Claude requested tool execution, run the tools and send results back
    if result[:tool_calls]&.any?
      tool_results = execute_tool_calls(result[:tool_calls])

      # Save tool results as a tool-role message
      save_message(
        role: "tool",
        content: tool_results.to_json,
        tool_results: tool_results
      )

      # Build the follow-up messages including tool results for Claude
      followup_messages = messages + [
        { role: "assistant", content: build_assistant_content_blocks(result) },
        { role: "user", content: build_tool_result_blocks(tool_results) }
      ]

      # Send tool results back to Claude for a final response
      followup_result = @claude.chat(
        messages: followup_messages,
        system: system_prompt,
        tools: ClaudeClient::TOOL_DEFINITIONS,
        max_tokens: 1024
      )

      total_tokens += (followup_result[:usage][:input_tokens] || 0) + (followup_result[:usage][:output_tokens] || 0)

      final_message = save_message(
        role: "assistant",
        content: followup_result[:content].presence || "",
        token_count: total_tokens
      )

      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
      update_session_metadata(followup_result[:usage], elapsed_ms)

      {
        response_text: followup_result[:content],
        tool_calls: result[:tool_calls],
        tool_results: tool_results,
        latency_ms: elapsed_ms,
        usage: { input_tokens: total_tokens - (followup_result[:usage][:output_tokens] || 0), output_tokens: followup_result[:usage][:output_tokens] || 0 },
        message_id: final_message.id
      }
    else
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
      update_session_metadata(result[:usage], elapsed_ms)

      {
        response_text: result[:content],
        tool_calls: nil,
        tool_results: nil,
        latency_ms: elapsed_ms,
        usage: result[:usage],
        message_id: assistant_message.id
      }
    end
  end

  def build_system_prompt(driving_state)
    parts = [BASE_SYSTEM_PROMPT.strip]

    parts << DRIVING_STATE_PROMPTS.fetch(driving_state, DRIVING_STATE_PROMPTS["unknown"])

    preference = user.user_preference
    if preference
      parts << "User preferences: verbosity=#{preference.response_verbosity}, " \
               "language=#{preference.language}, voice_speed=#{preference.voice_speed}."
    end

    if @session&.vehicle
      vehicle = @session.vehicle
      parts << "Vehicle: #{vehicle.year} #{vehicle.make} #{vehicle.model}."

      vehicle_state = VehicleContextService.new.get_state(vehicle.id)
      if vehicle_state
        parts << "Vehicle state: #{vehicle_state.to_json}."
      end
    end

    parts.join("\n\n")
  end

  def get_conversation_history(limit: 20)
    return [] unless @session

    @session.conversation_messages
      .order(created_at: :asc)
      .where(role: %w[user assistant])
      .last(limit)
  end

  private

  def execute_tool_calls(tool_calls)
    @orchestrator.execute_tool_calls(tool_calls, user: user)
  rescue Integrations::Orchestrator::ToolExecutionError => e
    Rails.logger.error("[ContextManager] Tool execution failed: #{e.message}")
    [{ tool_use_id: "error", tool_name: "unknown", result: { success: false, data: {}, error: e.message } }]
  end

  def build_assistant_content_blocks(result)
    blocks = []
    blocks << { type: "text", text: result[:content] } if result[:content].present?
    result[:tool_calls]&.each do |tc|
      blocks << { type: "tool_use", id: tc[:id], name: tc[:name], input: tc[:input] }
    end
    blocks
  end

  def build_tool_result_blocks(tool_results)
    tool_results.map do |tr|
      {
        type: "tool_result",
        tool_use_id: tr[:tool_use_id],
        content: JSON.generate(tr[:result])
      }
    end
  end

  def save_message(role:, content:, tool_calls: nil, tool_results: nil, token_count: nil, latency_ms: nil)
    @session.conversation_messages.create!(
      role: role,
      content: content.presence || " ",
      tool_calls: tool_calls,
      tool_results: tool_results,
      token_count: token_count,
      latency_ms: latency_ms
    )
  end

  def cache_session_data
    @cache.set_session(@session.id, {
      user_id: user.id,
      vehicle_id: @session.vehicle_id,
      started_at: @session.started_at.iso8601,
      driving_state: @session.driving_state
    })
  end

  def update_session_metadata(usage, latency_ms)
    metadata = @session.metadata || {}
    metadata["total_input_tokens"] = (metadata["total_input_tokens"] || 0) + (usage[:input_tokens] || 0)
    metadata["total_output_tokens"] = (metadata["total_output_tokens"] || 0) + (usage[:output_tokens] || 0)
    metadata["total_messages"] = (metadata["total_messages"] || 0) + 2
    metadata["avg_latency_ms"] = (
      ((metadata["avg_latency_ms"] || 0) * ((metadata["total_messages"] || 2) - 2) + latency_ms) /
      (metadata["total_messages"] || 2).to_f
    ).round

    @session.update!(metadata: metadata)
    cache_session_data
  end
end
