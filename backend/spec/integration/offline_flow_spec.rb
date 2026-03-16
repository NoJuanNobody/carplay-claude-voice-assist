# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Offline flow", type: :integration do
  let(:fallback_service) { Offline::FallbackResponseService.new }
  let(:network_status) { Offline::NetworkStatusService.new }

  describe "fallback responses when Claude API is down" do
    it "returns a navigation fallback response for navigation queries" do
      response = fallback_service.get_response(nil, text: "Navigate to the nearest gas station")

      expect(response[:source]).to eq("offline_fallback")
      expect(response[:category]).to eq(:navigation)
      expect(response[:text]).to be_present
      expect(response[:detected_at]).to be_present
      expect(Offline::FallbackResponseService::NAVIGATION_RESPONSES).to include(response[:text])
    end

    it "returns a weather fallback response for weather queries" do
      response = fallback_service.get_response(nil, text: "What's the temperature outside?")

      expect(response[:category]).to eq(:weather)
      expect(Offline::FallbackResponseService::WEATHER_RESPONSES).to include(response[:text])
    end

    it "returns a music fallback response for music queries" do
      response = fallback_service.get_response(nil, text: "Play my favorite playlist")

      expect(response[:category]).to eq(:music)
      expect(Offline::FallbackResponseService::MUSIC_RESPONSES).to include(response[:text])
    end

    it "returns a messages fallback response for messaging queries" do
      response = fallback_service.get_response(nil, text: "Send a text message to Mom")

      expect(response[:category]).to eq(:messages)
      expect(Offline::FallbackResponseService::MESSAGES_RESPONSES).to include(response[:text])
    end

    it "returns an emergency fallback response for emergency queries" do
      response = fallback_service.get_response(nil, text: "Emergency! I need help!")

      expect(response[:category]).to eq(:emergency)
      expect(Offline::FallbackResponseService::EMERGENCY_RESPONSES).to include(response[:text])
    end

    it "returns a general fallback response for unrecognized queries" do
      response = fallback_service.get_response(nil, text: "Tell me a joke about penguins")

      expect(response[:category]).to eq(:general)
      expect(Offline::FallbackResponseService::GENERAL_RESPONSES).to include(response[:text])
    end

    it "accepts an explicit intent parameter" do
      response = fallback_service.get_response(:navigation)

      expect(response[:category]).to eq(:navigation)
      expect(response[:source]).to eq("offline_fallback")
    end

    it "falls back to general when explicit intent is unrecognized" do
      response = fallback_service.get_response(:nonexistent_category)

      expect(response[:category]).to eq(:general)
    end
  end

  describe "intent detection accuracy" do
    {
      "Where is the nearest gas station?" => :navigation,
      "How far is it to downtown?" => :navigation,
      "Give me directions to the airport" => :navigation,
      "What's the weather forecast for tomorrow?" => :weather,
      "Is it going to rain today?" => :weather,
      "What's the temperature in celsius?" => :weather,
      "Play some jazz music" => :music,
      "Skip to the next track" => :music,
      "Pause the song" => :music,
      "Read my text messages" => :messages,
      "Send a message to John" => :messages,
      "Call my wife" => :messages,
      "Emergency! I need an ambulance" => :emergency,
      "Help me, there's been an accident" => :emergency,
      "Call 911 right now" => :emergency,
      "What time is it?" => :general,
      "Tell me a fun fact" => :general,
      "" => :general,
    }.each do |input, expected_category|
      it "detects '#{input.truncate(50)}' as #{expected_category}" do
        detected = fallback_service.detect_intent(input)
        expect(detected).to eq(expected_category)
      end
    end

    it "prioritizes emergency over other categories" do
      # Text contains both navigation and emergency keywords
      detected = fallback_service.detect_intent("There was an accident, navigate me to the hospital")
      expect(detected).to eq(:emergency)
    end
  end

  describe "network status service" do
    it "checks all services and returns their statuses" do
      # Stub the individual service checks
      allow_any_instance_of(Offline::NetworkStatusService).to receive(:check_service).with(:claude_api).and_return(:unhealthy)
      allow_any_instance_of(Offline::NetworkStatusService).to receive(:check_service).with(:redis).and_return(:healthy)
      allow_any_instance_of(Offline::NetworkStatusService).to receive(:check_service).with(:postgres).and_return(:healthy)

      results = network_status.check_all

      expect(results[:claude_api]).to eq(:unhealthy)
      expect(results[:redis]).to eq(:healthy)
      expect(results[:postgres]).to eq(:healthy)
    end

    it "reports healthy? as false when any service is down" do
      allow_any_instance_of(Offline::NetworkStatusService).to receive(:check_service).with(:claude_api).and_return(:unhealthy)
      allow_any_instance_of(Offline::NetworkStatusService).to receive(:check_service).with(:redis).and_return(:healthy)
      allow_any_instance_of(Offline::NetworkStatusService).to receive(:check_service).with(:postgres).and_return(:healthy)

      expect(network_status.healthy?).to be false
    end

    it "reports healthy? as true when all services are up" do
      allow_any_instance_of(Offline::NetworkStatusService).to receive(:check_service).and_return(:healthy)

      expect(network_status.healthy?).to be true
    end

    it "lists degraded services" do
      allow_any_instance_of(Offline::NetworkStatusService).to receive(:check_service).with(:claude_api).and_return(:unhealthy)
      allow_any_instance_of(Offline::NetworkStatusService).to receive(:check_service).with(:redis).and_return(:unhealthy)
      allow_any_instance_of(Offline::NetworkStatusService).to receive(:check_service).with(:postgres).and_return(:healthy)

      degraded = network_status.degraded_services

      expect(degraded).to contain_exactly(:claude_api, :redis)
    end

    it "handles unknown service names gracefully" do
      status = network_status.check_service(:unknown_service)
      expect(status).to eq(:unhealthy)
    end
  end

  describe "fallback response variety" do
    it "provides multiple response variants for each category" do
      fallback_service.categories.each do |category|
        count = fallback_service.response_count(category)
        if category == :general
          expect(count).to be >= 1
        else
          expect(count).to be >= 3, "Expected at least 3 responses for #{category}, got #{count}"
        end
      end
    end

    it "returns different responses on repeated calls (probabilistic)" do
      responses = 20.times.map { fallback_service.get_response(:navigation)[:text] }
      unique_count = responses.uniq.length
      expect(unique_count).to be > 1, "Expected varied responses but got #{unique_count} unique out of 20"
    end
  end
end
