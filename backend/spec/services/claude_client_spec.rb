# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClaudeClient do
  let(:api_key) { "test-api-key" }
  let(:client) { described_class.new(api_key: api_key) }

  let(:success_response_body) do
    {
      "id" => "msg_123",
      "type" => "message",
      "role" => "assistant",
      "content" => [
        { "type" => "text", "text" => "Hello! How can I help?" }
      ],
      "stop_reason" => "end_turn",
      "usage" => {
        "input_tokens" => 25,
        "output_tokens" => 10
      }
    }.to_json
  end

  let(:tool_use_response_body) do
    {
      "id" => "msg_456",
      "type" => "message",
      "role" => "assistant",
      "content" => [
        { "type" => "text", "text" => "I'll navigate you there." },
        {
          "type" => "tool_use",
          "id" => "toolu_123",
          "name" => "navigate_to",
          "input" => { "destination" => "123 Main St" }
        }
      ],
      "stop_reason" => "tool_use",
      "usage" => {
        "input_tokens" => 50,
        "output_tokens" => 30
      }
    }.to_json
  end

  let(:mock_connection) { instance_double(Faraday::Connection) }

  before do
    allow(Faraday).to receive(:new).and_return(mock_connection)
    allow(mock_connection).to receive(:options).and_return(
      OpenStruct.new(timeout: nil, open_timeout: nil)
    )
    allow(mock_connection).to receive(:headers).and_return({})
    allow(mock_connection).to receive(:adapter)
  end

  describe "#initialize" do
    it "uses provided API key" do
      client = described_class.new(api_key: "my-key")
      expect(client).to be_a(described_class)
    end

    it "falls back to ENV variable" do
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY").and_return("env-key")
      client = described_class.new
      expect(client).to be_a(described_class)
    end
  end

  describe "#chat" do
    it "returns parsed response with text content" do
      response = instance_double(Faraday::Response, status: 200, body: success_response_body)
      allow(mock_connection).to receive(:post).and_yield(
        OpenStruct.new(body: nil)
      ).and_return(response)

      result = client.chat(messages: [{ role: "user", content: "Hi" }])

      expect(result[:role]).to eq("assistant")
      expect(result[:content]).to eq("Hello! How can I help?")
      expect(result[:tool_calls]).to be_nil
      expect(result[:usage][:input_tokens]).to eq(25)
      expect(result[:usage][:output_tokens]).to eq(10)
      expect(result[:stop_reason]).to eq("end_turn")
    end

    it "returns parsed response with tool calls" do
      response = instance_double(Faraday::Response, status: 200, body: tool_use_response_body)
      allow(mock_connection).to receive(:post).and_yield(
        OpenStruct.new(body: nil)
      ).and_return(response)

      result = client.chat(messages: [{ role: "user", content: "Navigate to 123 Main St" }])

      expect(result[:content]).to eq("I'll navigate you there.")
      expect(result[:tool_calls]).to be_an(Array)
      expect(result[:tool_calls].length).to eq(1)
      expect(result[:tool_calls].first[:name]).to eq("navigate_to")
      expect(result[:tool_calls].first[:input]).to eq({ "destination" => "123 Main St" })
    end

    it "raises ApiError on 400 status" do
      error_body = { "error" => { "message" => "Bad request" } }.to_json
      response = instance_double(Faraday::Response, status: 400, body: error_body)
      allow(mock_connection).to receive(:post).and_yield(
        OpenStruct.new(body: nil)
      ).and_return(response)

      expect {
        client.chat(messages: [{ role: "user", content: "Hi" }])
      }.to raise_error(ClaudeClient::ApiError, /Client error/)
    end

    it "retries on rate limit and raises after max retries" do
      error_body = { "error" => { "message" => "Rate limited" } }.to_json
      response = instance_double(Faraday::Response, status: 429, body: error_body)
      allow(mock_connection).to receive(:post).and_yield(
        OpenStruct.new(body: nil)
      ).and_return(response)
      allow(client).to receive(:sleep)

      expect {
        client.chat(messages: [{ role: "user", content: "Hi" }])
      }.to raise_error(ClaudeClient::RateLimitError)
    end

    it "retries on timeout and raises after max retries" do
      allow(mock_connection).to receive(:post).and_raise(Faraday::TimeoutError)
      allow(client).to receive(:sleep)

      expect {
        client.chat(messages: [{ role: "user", content: "Hi" }])
      }.to raise_error(ClaudeClient::TimeoutError)
    end

    it "retries on connection failure and raises after max retries" do
      allow(mock_connection).to receive(:post).and_raise(Faraday::ConnectionFailed.new("refused"))
      allow(client).to receive(:sleep)

      expect {
        client.chat(messages: [{ role: "user", content: "Hi" }])
      }.to raise_error(ClaudeClient::ApiError, /Connection failed/)
    end

    it "passes system prompt when provided" do
      response = instance_double(Faraday::Response, status: 200, body: success_response_body)
      request_stub = OpenStruct.new(body: nil)
      allow(mock_connection).to receive(:post).and_yield(request_stub).and_return(response)

      client.chat(
        messages: [{ role: "user", content: "Hi" }],
        system: "You are a car assistant"
      )

      sent_body = JSON.parse(request_stub.body)
      expect(sent_body["system"]).to eq("You are a car assistant")
    end

    it "passes tools when provided" do
      response = instance_double(Faraday::Response, status: 200, body: success_response_body)
      request_stub = OpenStruct.new(body: nil)
      allow(mock_connection).to receive(:post).and_yield(request_stub).and_return(response)

      tools = [{ name: "test_tool", description: "A test", input_schema: { type: "object", properties: {} } }]
      client.chat(
        messages: [{ role: "user", content: "Hi" }],
        tools: tools
      )

      sent_body = JSON.parse(request_stub.body)
      expect(sent_body["tools"]).to be_an(Array)
      expect(sent_body["tools"].first["name"]).to eq("test_tool")
    end
  end

  describe "#chat_with_tools" do
    it "sets requires_tool_execution flag when tool calls present" do
      response = instance_double(Faraday::Response, status: 200, body: tool_use_response_body)
      allow(mock_connection).to receive(:post).and_yield(
        OpenStruct.new(body: nil)
      ).and_return(response)

      result = client.chat_with_tools(
        messages: [{ role: "user", content: "Navigate home" }]
      )

      expect(result[:requires_tool_execution]).to be true
      expect(result[:tool_calls]).to be_present
    end

    it "does not set requires_tool_execution when no tool calls" do
      response = instance_double(Faraday::Response, status: 200, body: success_response_body)
      allow(mock_connection).to receive(:post).and_yield(
        OpenStruct.new(body: nil)
      ).and_return(response)

      result = client.chat_with_tools(
        messages: [{ role: "user", content: "Hello" }]
      )

      expect(result[:requires_tool_execution]).to be_nil
    end

    it "uses default tool definitions" do
      response = instance_double(Faraday::Response, status: 200, body: success_response_body)
      request_stub = OpenStruct.new(body: nil)
      allow(mock_connection).to receive(:post).and_yield(request_stub).and_return(response)

      client.chat_with_tools(messages: [{ role: "user", content: "Hi" }])

      sent_body = JSON.parse(request_stub.body)
      tool_names = sent_body["tools"].map { |t| t["name"] }
      expect(tool_names).to include(
        "navigate_to", "send_message", "read_messages",
        "get_calendar_events", "play_music", "get_weather",
        "set_reminder", "get_vehicle_status"
      )
    end
  end

  describe "TOOL_DEFINITIONS" do
    it "defines 8 tools" do
      expect(ClaudeClient::TOOL_DEFINITIONS.length).to eq(8)
    end

    it "each tool has name, description, and input_schema" do
      ClaudeClient::TOOL_DEFINITIONS.each do |tool|
        expect(tool[:name]).to be_present
        expect(tool[:description]).to be_present
        expect(tool[:input_schema]).to be_a(Hash)
        expect(tool[:input_schema][:type]).to eq("object")
      end
    end
  end
end
