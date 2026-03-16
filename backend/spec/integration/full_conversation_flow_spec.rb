# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Full conversation flow", type: :integration do
  let!(:user) { create(:user, :with_preference) }
  let!(:vehicle) { create(:vehicle, user: user) }
  let(:context_manager) { ContextManager.new(user: user) }
  let(:response_validator) { Safety::ResponseValidator.new }

  let(:claude_text_response) do
    {
      "content" => [
        { "type" => "text", "text" => "I'll start navigation to the airport for you." }
      ],
      "role" => "assistant",
      "stop_reason" => "end_turn",
      "usage" => { "input_tokens" => 120, "output_tokens" => 25 }
    }
  end

  let(:claude_tool_response) do
    {
      "content" => [
        { "type" => "text", "text" => "Let me navigate you there." },
        {
          "type" => "tool_use",
          "id" => "tool_abc123",
          "name" => "navigate_to",
          "input" => { "destination" => "San Francisco Airport" }
        }
      ],
      "role" => "assistant",
      "stop_reason" => "tool_use",
      "usage" => { "input_tokens" => 150, "output_tokens" => 40 }
    }
  end

  let(:claude_followup_response) do
    {
      "content" => [
        { "type" => "text", "text" => "I've started navigation to San Francisco Airport. The estimated time is about 25 minutes." }
      ],
      "role" => "assistant",
      "stop_reason" => "end_turn",
      "usage" => { "input_tokens" => 200, "output_tokens" => 30 }
    }
  end

  before do
    # Stub CacheService to avoid Redis dependency
    cache_double = instance_double(CacheService)
    allow(CacheService).to receive(:new).and_return(cache_double)
    allow(cache_double).to receive(:set_session)
    allow(cache_double).to receive(:delete)
    allow(cache_double).to receive(:get_vehicle_state).and_return(nil)
    allow(cache_double).to receive(:set_vehicle_state)
  end

  describe "complete user session lifecycle" do
    it "creates a user, registers a vehicle, starts a session, sends a message, and ends the session" do
      # Step 1: Start a session
      session_result = context_manager.start_session(vehicle_id: vehicle.id)

      expect(session_result[:session_id]).to be_present
      expect(session_result[:session_token]).to be_present
      expect(session_result[:started_at]).to be_present

      session = VoiceSession.find(session_result[:session_id])
      expect(session.user).to eq(user)
      expect(session.vehicle).to eq(vehicle)
      expect(session.driving_state).to eq("unknown")

      # Step 2: Send a message and get a text-only Claude response
      faraday_response = instance_double(Faraday::Response, status: 200, body: JSON.generate(claude_text_response))
      allow_any_instance_of(Faraday::Connection).to receive(:post).and_return(faraday_response)

      message_result = context_manager.process_message("What's the weather like?", driving_state: "city")

      expect(message_result[:response_text]).to eq("I'll start navigation to the airport for you.")
      expect(message_result[:latency_ms]).to be_a(Integer)
      expect(message_result[:message_id]).to be_present
      expect(message_result[:tool_calls]).to be_nil

      # Verify messages were saved
      messages = session.conversation_messages.order(:created_at)
      expect(messages.count).to eq(2)
      expect(messages.first.role).to eq("user")
      expect(messages.first.content).to eq("What's the weather like?")
      expect(messages.last.role).to eq("assistant")

      # Step 3: Validate the response passes safety checks
      validation = response_validator.validate(message_result[:response_text], driving_state: :city)
      expect(validation[:valid]).to be true

      # Step 4: End the session
      end_result = context_manager.end_session

      expect(end_result[:session_id]).to eq(session.id)
      expect(end_result[:ended_at]).to be_present
      expect(end_result[:message_count]).to eq(2)

      session.reload
      expect(session.ended_at).to be_present
    end

    it "handles a full tool-call flow with navigation" do
      session_result = context_manager.start_session(vehicle_id: vehicle.id)
      session = VoiceSession.find(session_result[:session_id])

      # First call returns tool_use, second call returns followup text
      tool_faraday = instance_double(Faraday::Response, status: 200, body: JSON.generate(claude_tool_response))
      followup_faraday = instance_double(Faraday::Response, status: 200, body: JSON.generate(claude_followup_response))

      call_count = 0
      allow_any_instance_of(Faraday::Connection).to receive(:post) do
        call_count += 1
        call_count == 1 ? tool_faraday : followup_faraday
      end

      result = context_manager.process_message("Navigate to San Francisco Airport", driving_state: "city")

      # Verify tool was called
      expect(result[:tool_calls]).to be_present
      expect(result[:tool_calls].first[:name]).to eq("navigate_to")
      expect(result[:tool_calls].first[:input]["destination"]).to eq("San Francisco Airport")

      # Verify tool results
      expect(result[:tool_results]).to be_present
      expect(result[:tool_results].first[:tool_name]).to eq("navigate_to")
      expect(result[:tool_results].first[:result][:success]).to be true
      expect(result[:tool_results].first[:result][:data][:navigation_started]).to be true

      # Verify final response
      expect(result[:response_text]).to include("San Francisco Airport")

      # Verify safety of the final response
      validation = response_validator.validate(result[:response_text], driving_state: :city)
      expect(validation[:valid]).to be true

      # Verify session metadata was updated
      session.reload
      metadata = session.metadata
      expect(metadata["total_messages"]).to be > 0
      expect(metadata["avg_latency_ms"]).to be_a(Numeric)
    end
  end

  describe "metrics recording" do
    before do
      Metrics::Collector.instance.reset!
    end

    it "records session events in the metrics collector" do
      Metrics::Collector.instance.record_session_event(:start)

      snapshot = Metrics::Collector.instance.snapshot
      expect(snapshot[:active_sessions]).to eq(1)

      Metrics::Collector.instance.record_session_event(:end)

      snapshot = Metrics::Collector.instance.snapshot
      expect(snapshot[:active_sessions]).to eq(0)
    end

    it "records request metrics" do
      Metrics::Collector.instance.record_request("/api/v1/sessions", "POST", 200, 150)
      Metrics::Collector.instance.record_request("/api/v1/sessions/1/messages", "POST", 200, 2500)

      snapshot = Metrics::Collector.instance.snapshot
      expect(snapshot[:requests_total]).to eq(2)
      expect(snapshot[:avg_response_ms]).to eq(1325.0)
      expect(snapshot[:errors_total]).to eq(0)
    end
  end
end
