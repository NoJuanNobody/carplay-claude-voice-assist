# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContextManager do
  let(:mock_redis) { instance_double(Redis) }
  let(:user) { create(:user, :with_preference) }
  let(:vehicle) { create(:vehicle, user: user) }

  before do
    stub_const("REDIS", mock_redis)
    allow(mock_redis).to receive(:setex)
    allow(mock_redis).to receive(:get).and_return(nil)
    allow(mock_redis).to receive(:del)
    allow(mock_redis).to receive(:exists?).and_return(false)
  end

  describe "#start_session" do
    it "creates a new voice session" do
      manager = described_class.new(user: user)

      expect {
        result = manager.start_session
        expect(result[:session_id]).to be_present
        expect(result[:session_token]).to be_present
        expect(result[:started_at]).to be_present
      }.to change(VoiceSession, :count).by(1)
    end

    it "associates vehicle when vehicle_id provided" do
      manager = described_class.new(user: user)
      result = manager.start_session(vehicle_id: vehicle.id)

      session = VoiceSession.find(result[:session_id])
      expect(session.vehicle).to eq(vehicle)
    end

    it "caches session data" do
      manager = described_class.new(user: user)
      manager.start_session

      expect(mock_redis).to have_received(:setex).with(
        /carplay:session:/,
        1800,
        anything
      )
    end

    it "raises error for invalid vehicle_id" do
      manager = described_class.new(user: user)

      expect {
        manager.start_session(vehicle_id: SecureRandom.uuid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#end_session" do
    it "marks session as ended" do
      manager = described_class.new(user: user)
      manager.start_session

      result = manager.end_session

      expect(result[:ended_at]).to be_present
      expect(result[:session_id]).to be_present
    end

    it "clears session cache" do
      manager = described_class.new(user: user)
      manager.start_session
      manager.end_session

      expect(mock_redis).to have_received(:del).with(/carplay:session:/)
    end

    it "raises error without active session" do
      manager = described_class.new(user: user)

      expect {
        manager.end_session
      }.to raise_error(ContextManager::SessionError, "No active session")
    end
  end

  describe "#process_message" do
    let(:session) { create(:voice_session, user: user, vehicle: vehicle) }
    let(:manager) { described_class.new(user: user, session: session) }
    let(:claude_response) do
      {
        role: "assistant",
        content: "I can help with that!",
        tool_calls: nil,
        stop_reason: "end_turn",
        usage: { input_tokens: 100, output_tokens: 50 }
      }
    end

    before do
      allow_any_instance_of(ClaudeClient).to receive(:chat_with_tools).and_return(claude_response)
    end

    it "saves user and assistant messages" do
      expect {
        manager.process_message("Hello")
      }.to change(ConversationMessage, :count).by(2)

      messages = session.conversation_messages.order(:created_at)
      expect(messages.first.role).to eq("user")
      expect(messages.first.content).to eq("Hello")
      expect(messages.last.role).to eq("assistant")
      expect(messages.last.content).to eq("I can help with that!")
    end

    it "returns response with latency" do
      result = manager.process_message("Hello")

      expect(result[:response_text]).to eq("I can help with that!")
      expect(result[:latency_ms]).to be_a(Integer)
      expect(result[:usage]).to eq({ input_tokens: 100, output_tokens: 50 })
      expect(result[:message_id]).to be_present
    end

    it "returns tool calls when present" do
      tool_response = claude_response.merge(
        tool_calls: [{ id: "toolu_1", name: "navigate_to", input: { "destination" => "Home" } }]
      )
      allow_any_instance_of(ClaudeClient).to receive(:chat_with_tools).and_return(tool_response)

      result = manager.process_message("Navigate home")
      expect(result[:tool_calls]).to be_present
      expect(result[:tool_calls].first[:name]).to eq("navigate_to")
    end

    it "updates session metadata with token usage" do
      manager.process_message("Hello")
      session.reload

      expect(session.metadata["total_input_tokens"]).to eq(100)
      expect(session.metadata["total_output_tokens"]).to eq(50)
      expect(session.metadata["total_messages"]).to eq(2)
    end

    it "raises error without active session" do
      mgr = described_class.new(user: user)

      expect {
        mgr.process_message("Hello")
      }.to raise_error(ContextManager::SessionError, "No active session")
    end

    it "raises error when session has ended" do
      session.update!(ended_at: Time.current)

      expect {
        manager.process_message("Hello")
      }.to raise_error(ContextManager::SessionError, "Session has ended")
    end

    it "updates driving state on session" do
      manager.process_message("Hello", driving_state: "driving")
      session.reload

      expect(session.driving_state).to eq("driving")
    end
  end

  describe "#build_system_prompt" do
    let(:session) { create(:voice_session, user: user, vehicle: vehicle) }
    let(:manager) { described_class.new(user: user, session: session) }

    it "includes base system prompt" do
      prompt = manager.build_system_prompt("parked")
      expect(prompt).to include("voice assistant")
      expect(prompt).to include("CarPlay")
    end

    it "includes driving state instructions for parked" do
      prompt = manager.build_system_prompt("parked")
      expect(prompt).to include("currently parked")
      expect(prompt).to include("detailed responses")
    end

    it "includes driving state instructions for driving" do
      prompt = manager.build_system_prompt("driving")
      expect(prompt).to include("actively driving")
      expect(prompt).to include("extremely brief")
    end

    it "includes user preferences" do
      prompt = manager.build_system_prompt("unknown")
      expect(prompt).to include("verbosity=concise")
    end

    it "includes vehicle information" do
      prompt = manager.build_system_prompt("unknown")
      expect(prompt).to include(vehicle.make)
      expect(prompt).to include(vehicle.model)
    end

    it "defaults to unknown driving state for unrecognized states" do
      prompt = manager.build_system_prompt("flying")
      expect(prompt).to include("unknown")
      expect(prompt).to include("safety-first")
    end
  end

  describe "#get_conversation_history" do
    let(:session) { create(:voice_session, user: user) }
    let(:manager) { described_class.new(user: user, session: session) }

    it "returns recent messages in order" do
      create(:conversation_message, voice_session: session, role: "user", content: "First", created_at: 2.minutes.ago)
      create(:conversation_message, voice_session: session, role: "assistant", content: "Response", created_at: 1.minute.ago)

      history = manager.get_conversation_history
      expect(history.length).to eq(2)
      expect(history.first.content).to eq("First")
      expect(history.last.content).to eq("Response")
    end

    it "respects the limit parameter" do
      25.times do |i|
        create(:conversation_message, voice_session: session, role: "user", content: "Message #{i}")
      end

      history = manager.get_conversation_history(limit: 10)
      expect(history.length).to eq(10)
    end

    it "excludes system and tool messages" do
      create(:conversation_message, voice_session: session, role: "user", content: "Hi")
      create(:conversation_message, voice_session: session, role: "system", content: "System msg")
      create(:conversation_message, voice_session: session, role: "tool", content: "Tool result")

      history = manager.get_conversation_history
      expect(history.length).to eq(1)
      expect(history.first.role).to eq("user")
    end

    it "returns empty array without session" do
      mgr = described_class.new(user: user)
      expect(mgr.get_conversation_history).to eq([])
    end
  end
end
