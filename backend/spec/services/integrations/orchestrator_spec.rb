# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Orchestrator do
  let(:orchestrator) { described_class.new }
  let(:user) { create(:user) }

  describe "#execute_tool_call" do
    context "with navigate_to" do
      it "dispatches to MapsAdapter and returns success" do
        result = orchestrator.execute_tool_call(
          "navigate_to",
          { "destination" => "123 Main Street" },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:destination]).to eq("123 Main Street")
        expect(result.data[:navigation_started]).to be true
        expect(result.data[:estimated_travel_time_minutes]).to be_a(Integer)
      end
    end

    context "with send_message" do
      it "dispatches to MessagesAdapter and returns success" do
        result = orchestrator.execute_tool_call(
          "send_message",
          { "contact" => "Mom", "message" => "On my way!" },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:contact]).to eq("Mom")
        expect(result.data[:sent]).to be true
      end
    end

    context "with read_messages" do
      it "dispatches to MessagesAdapter for reading" do
        result = orchestrator.execute_tool_call(
          "read_messages",
          { "contact" => "Mom", "unread_only" => true },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:messages]).to be_an(Array)
      end
    end

    context "with get_calendar_events" do
      it "dispatches to CalendarAdapter" do
        result = orchestrator.execute_tool_call(
          "get_calendar_events",
          { "date" => "2026-03-16", "limit" => 3 },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:events]).to be_an(Array)
        expect(result.data[:events].length).to be <= 3
      end
    end

    context "with set_reminder" do
      it "dispatches to CalendarAdapter for reminders" do
        result = orchestrator.execute_tool_call(
          "set_reminder",
          { "text" => "Pick up groceries", "time" => "in 30 minutes" },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:text]).to eq("Pick up groceries")
        expect(result.data[:created]).to be true
      end
    end

    context "with play_music" do
      it "dispatches to MediaAdapter" do
        result = orchestrator.execute_tool_call(
          "play_music",
          { "action" => "play", "query" => "Bohemian Rhapsody" },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:state]).to eq("playing")
      end
    end

    context "with get_weather" do
      it "dispatches to WeatherAdapter" do
        result = orchestrator.execute_tool_call(
          "get_weather",
          { "location" => "San Francisco", "forecast" => true },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:location]).to eq("San Francisco")
        expect(result.data[:forecast]).to be_an(Array)
      end
    end

    context "with get_vehicle_status" do
      let(:vehicle) { create(:vehicle, user: user) }
      let(:mock_redis) { instance_double(Redis) }

      before do
        stub_const("REDIS", mock_redis)
        allow(mock_redis).to receive(:get).and_return(nil)
        allow(mock_redis).to receive(:setex)
        vehicle # ensure vehicle is created
      end

      it "dispatches to VehicleAdapter" do
        result = orchestrator.execute_tool_call(
          "get_vehicle_status",
          { "info_type" => "all" },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:vehicle]).to include(vehicle.make)
      end
    end

    context "with unknown tool" do
      it "raises UnknownToolError" do
        expect {
          orchestrator.execute_tool_call("fly_to_moon", {}, user: user)
        }.to raise_error(Integrations::Orchestrator::UnknownToolError, /Unknown tool.*fly_to_moon/)
      end
    end

    context "when adapter raises a validation error" do
      it "returns an error result without raising" do
        result = orchestrator.execute_tool_call(
          "navigate_to",
          {},
          user: user
        )

        expect(result.success).to be false
        expect(result.error).to include("Missing required fields")
      end
    end
  end

  describe "#execute_tool_calls" do
    it "executes multiple tool calls and returns all results" do
      tool_calls = [
        { id: "toolu_1", name: "get_weather", input: { "location" => "NYC" } },
        { id: "toolu_2", name: "navigate_to", input: { "destination" => "Airport" } }
      ]

      results = orchestrator.execute_tool_calls(tool_calls, user: user)

      expect(results.length).to eq(2)
      expect(results[0][:tool_use_id]).to eq("toolu_1")
      expect(results[0][:tool_name]).to eq("get_weather")
      expect(results[0][:result][:success]).to be true
      expect(results[1][:tool_use_id]).to eq("toolu_2")
      expect(results[1][:tool_name]).to eq("navigate_to")
      expect(results[1][:result][:success]).to be true
    end

    it "handles mixed success and failure results" do
      tool_calls = [
        { id: "toolu_1", name: "get_weather", input: {} },
        { id: "toolu_2", name: "navigate_to", input: {} }
      ]

      results = orchestrator.execute_tool_calls(tool_calls, user: user)

      weather_result = results.find { |r| r[:tool_name] == "get_weather" }
      nav_result = results.find { |r| r[:tool_name] == "navigate_to" }

      expect(weather_result[:result][:success]).to be true
      expect(nav_result[:result][:success]).to be false
    end
  end

  describe "#available_tools" do
    it "returns all registered tool names" do
      tools = orchestrator.available_tools
      expect(tools).to include("navigate_to", "send_message", "read_messages",
                               "get_calendar_events", "set_reminder", "play_music",
                               "get_weather", "get_vehicle_status")
    end
  end

  describe "#tool_registered?" do
    it "returns true for registered tools" do
      expect(orchestrator.tool_registered?("navigate_to")).to be true
    end

    it "returns false for unregistered tools" do
      expect(orchestrator.tool_registered?("teleport")).to be false
    end
  end
end
