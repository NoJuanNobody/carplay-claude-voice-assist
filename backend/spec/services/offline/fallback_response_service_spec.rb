require "spec_helper"
require_relative "../../../app/services/offline/fallback_response_service"

RSpec.describe Offline::FallbackResponseService do
  subject(:service) { described_class.new }

  describe "#get_response" do
    it "returns a hash with the expected keys" do
      result = service.get_response(:general)
      expect(result).to include(:text, :source, :category, :detected_at)
    end

    it "sets source to offline_fallback" do
      result = service.get_response(:general)
      expect(result[:source]).to eq("offline_fallback")
    end

    it "returns a response for an explicit intent" do
      result = service.get_response(:navigation)
      expect(result[:category]).to eq(:navigation)
      expect(result[:text]).to be_a(String)
      expect(result[:text].length).to be > 0
    end

    it "falls back to general when intent is unknown" do
      result = service.get_response(:nonexistent_category)
      expect(result[:category]).to eq(:general)
    end

    it "detects intent from text when no explicit intent given" do
      result = service.get_response(nil, text: "navigate to the store")
      expect(result[:category]).to eq(:navigation)
    end

    it "defaults to general when no intent and no text provided" do
      result = service.get_response
      expect(result[:category]).to eq(:general)
    end

    it "includes a valid ISO 8601 timestamp" do
      result = service.get_response(:general)
      expect { Time.iso8601(result[:detected_at]) }.not_to raise_error
    end

    context "with each category" do
      %i[navigation weather music messages emergency general].each do |category|
        it "returns a non-empty response for #{category}" do
          result = service.get_response(category)
          expect(result[:text]).to be_a(String)
          expect(result[:text].length).to be > 10
          expect(result[:category]).to eq(category)
        end
      end
    end
  end

  describe "#detect_intent" do
    it "detects navigation intent" do
      expect(service.detect_intent("navigate to the nearest gas station")).to eq(:navigation)
      expect(service.detect_intent("give me directions home")).to eq(:navigation)
      expect(service.detect_intent("what's my route")).to eq(:navigation)
    end

    it "detects weather intent" do
      expect(service.detect_intent("what's the weather like")).to eq(:weather)
      expect(service.detect_intent("is it going to rain today")).to eq(:weather)
      expect(service.detect_intent("what's the temperature outside")).to eq(:weather)
      expect(service.detect_intent("will there be a storm tonight")).to eq(:weather)
    end

    it "detects music intent" do
      expect(service.detect_intent("play some jazz music")).to eq(:music)
      expect(service.detect_intent("skip this song")).to eq(:music)
      expect(service.detect_intent("turn up the volume")).to eq(:music)
    end

    it "detects messages intent" do
      expect(service.detect_intent("read my messages")).to eq(:messages)
      expect(service.detect_intent("send a text to mom")).to eq(:messages)
      expect(service.detect_intent("call John")).to eq(:messages)
    end

    it "detects emergency intent" do
      expect(service.detect_intent("there's been an accident")).to eq(:emergency)
      expect(service.detect_intent("call 911")).to eq(:emergency)
      expect(service.detect_intent("I need help")).to eq(:emergency)
    end

    it "prioritizes emergency over other categories" do
      expect(service.detect_intent("help navigate to hospital emergency")).to eq(:emergency)
    end

    it "returns general for unrecognized input" do
      expect(service.detect_intent("tell me a joke")).to eq(:general)
      expect(service.detect_intent("what is the meaning of life")).to eq(:general)
    end

    it "returns general for nil input" do
      expect(service.detect_intent(nil)).to eq(:general)
    end

    it "returns general for empty input" do
      expect(service.detect_intent("")).to eq(:general)
      expect(service.detect_intent("   ")).to eq(:general)
    end
  end

  describe "#categories" do
    it "returns all six categories" do
      expect(service.categories).to contain_exactly(
        :navigation, :weather, :music, :messages, :emergency, :general
      )
    end
  end

  describe "#response_count" do
    it "returns at least 5 responses per category" do
      %i[navigation weather music messages emergency general].each do |category|
        expect(service.response_count(category)).to be >= 5,
          "Expected at least 5 responses for #{category}, got #{service.response_count(category)}"
      end
    end

    it "returns 0 for unknown categories" do
      expect(service.response_count(:nonexistent)).to eq(0)
    end
  end
end
