# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Safety flow", type: :integration do
  let(:response_validator) { Safety::ResponseValidator.new }
  let(:emergency_handler) { Safety::EmergencyHandler.new }
  let!(:user) { create(:user) }
  let!(:vehicle) { create(:vehicle, user: user) }
  let!(:voice_session) { create(:voice_session, user: user, vehicle: vehicle) }

  describe "response truncation at different driving states" do
    let(:long_response) do
      "The weather today is sunny with a high of 75 degrees. " \
      "Tomorrow will be partly cloudy with a chance of rain in the afternoon. " \
      "Wednesday looks like it will be clear and warm. " \
      "Thursday may see some thunderstorms moving in from the west. " \
      "Friday should be nice again with temperatures in the low 70s. " \
      "The weekend forecast shows mostly sunny skies with moderate humidity. " \
      "Overall, it looks like a pleasant week ahead."
    end

    it "allows full responses when parked" do
      result = response_validator.validate(long_response, driving_state: :parked)

      expect(result[:valid]).to be true
      expect(result[:modified_text]).to eq(long_response)
      expect(result[:violations]).to be_empty
    end

    it "truncates responses to 4 sentences when driving in city" do
      result = response_validator.validate(long_response, driving_state: :city)

      expect(result[:violations]).to include(:response_too_long)
      sentences = result[:modified_text].scan(/[^.!?]+[.!?]+/).map(&:strip).reject(&:empty?)
      # The truncated text includes the original sentences plus the truncation notice sentence
      original_sentences = sentences.reject { |s| s.include?("parked") }
      expect(original_sentences.length).to be <= 4
    end

    it "truncates responses to 2 sentences on highway" do
      result = response_validator.validate(long_response, driving_state: :highway)

      expect(result[:violations]).to include(:response_too_long)
      sentences = result[:modified_text].scan(/[^.!?]+[.!?]+/).map(&:strip).reject(&:empty?)
      original_sentences = sentences.reject { |s| s.include?("parked") }
      expect(original_sentences.length).to be <= 2
    end

    it "truncates to 1 sentence in emergency state" do
      result = response_validator.validate(long_response, driving_state: :emergency)

      expect(result[:violations]).to include(:response_too_long)
      sentences = result[:modified_text].scan(/[^.!?]+[.!?]+/).map(&:strip).reject(&:empty?)
      original_sentences = sentences.reject { |s| s.include?("parked") }
      expect(original_sentences.length).to be <= 1
    end

    it "does not truncate short responses when driving" do
      short_response = "The weather is sunny and 75 degrees."
      result = response_validator.validate(short_response, driving_state: :highway)

      expect(result[:valid]).to be true
      expect(result[:modified_text]).to eq(short_response)
    end
  end

  describe "phone number redaction while driving" do
    let(:response_with_phone) { "You can reach them at 555-123-4567 for more information." }

    it "redacts phone numbers while driving in city" do
      result = response_validator.validate(response_with_phone, driving_state: :city)

      expect(result[:violations]).to include(:phone_number_while_driving)
      expect(result[:modified_text]).not_to include("555-123-4567")
      expect(result[:modified_text]).to include("[phone number hidden while driving]")
    end

    it "redacts phone numbers on the highway" do
      result = response_validator.validate(response_with_phone, driving_state: :highway)

      expect(result[:violations]).to include(:phone_number_while_driving)
      expect(result[:modified_text]).not_to include("555-123-4567")
    end

    it "does not redact phone numbers when parked" do
      result = response_validator.validate(response_with_phone, driving_state: :parked)

      expect(result[:valid]).to be true
      expect(result[:modified_text]).to include("555-123-4567")
    end

    it "redacts multiple phone number formats" do
      text_with_phones = "Call (800) 555-1234 or +1 212.555.6789 for assistance."
      result = response_validator.validate(text_with_phones, driving_state: :city)

      expect(result[:violations]).to include(:phone_number_while_driving)
      expect(result[:modified_text]).not_to match(/\d{3}[-.)]\d{3}[-.)]\d{4}/)
    end
  end

  describe "URL redaction while driving" do
    let(:response_with_url) { "Check out https://example.com/details for more info." }

    it "redacts URLs while driving" do
      result = response_validator.validate(response_with_url, driving_state: :city)

      expect(result[:violations]).to include(:url_while_driving)
      expect(result[:modified_text]).not_to include("https://example.com")
      expect(result[:modified_text]).to include("[link hidden while driving]")
    end

    it "does not redact URLs when parked" do
      result = response_validator.validate(response_with_url, driving_state: :parked)

      expect(result[:valid]).to be true
      expect(result[:modified_text]).to include("https://example.com/details")
    end
  end

  describe "emergency detection and event logging" do
    it "detects crash emergency keywords and logs the event" do
      result = emergency_handler.check(
        "I just crashed my car!",
        driving_state: :highway,
        user: user,
        voice_session: voice_session
      )

      expect(result[:emergency]).to be true
      expect(result[:type]).to eq(:crash_detected)
      expect(result[:action]).to eq(:call_911)

      # Verify the safety event was logged
      event = SafetyEvent.last
      expect(event).to be_present
      expect(event.user).to eq(user)
      expect(event.voice_session).to eq(voice_session)
      expect(event.event_type).to eq("emergency_crash_detected")
      expect(event.severity).to eq("critical")
      expect(event.metadata["emergency_type"]).to eq("crash_detected")
      expect(event.metadata["action"]).to eq("call_911")
    end

    it "detects medical emergency keywords" do
      result = emergency_handler.check(
        "I'm having chest pain",
        driving_state: :city,
        user: user,
        voice_session: voice_session
      )

      expect(result[:emergency]).to be true
      expect(result[:type]).to eq(:medical_emergency)
      expect(result[:action]).to eq(:call_911)
    end

    it "detects roadside assistance keywords" do
      result = emergency_handler.check(
        "I have a flat tire",
        driving_state: :city,
        user: user,
        voice_session: voice_session
      )

      expect(result[:emergency]).to be true
      expect(result[:type]).to eq(:roadside_assistance)
      expect(result[:action]).to eq(:call_roadside)
    end

    it "escalates roadside assistance to 911 on highway" do
      result = emergency_handler.check(
        "My car broke down",
        driving_state: :highway,
        user: user,
        voice_session: voice_session
      )

      expect(result[:emergency]).to be true
      expect(result[:type]).to eq(:roadside_assistance)
      expect(result[:action]).to eq(:call_911)
    end

    it "detects SOS keywords" do
      result = emergency_handler.check(
        "Help me, this is an emergency!",
        driving_state: :city,
        user: user,
        voice_session: voice_session
      )

      expect(result[:emergency]).to be true
      expect(result[:type]).to eq(:sos)
      expect(result[:action]).to eq(:call_911)
    end

    it "returns no emergency for normal input" do
      result = emergency_handler.check(
        "What's the weather like today?",
        driving_state: :city,
        user: user,
        voice_session: voice_session
      )

      expect(result[:emergency]).to be false
      expect(result[:type]).to be_nil
      expect(result[:action]).to be_nil
    end

    it "logs emergency events to the database" do
      expect {
        emergency_handler.check(
          "I think I'm having a stroke",
          driving_state: :city,
          user: user,
          voice_session: voice_session
        )
      }.to change(SafetyEvent, :count).by(1)

      event = SafetyEvent.last
      expect(event.event_type).to eq("emergency_medical_emergency")
      expect(event.metadata["detected_at"]).to be_present
    end
  end

  describe "combined safety pipeline" do
    it "validates and truncates a response that contains both a phone number and is too long while driving" do
      text = "For roadside assistance call 800-555-1234. " \
             "Your nearest service center is 5 miles away. " \
             "They can tow your vehicle for free. " \
             "Their hours are 8am to 6pm Monday through Friday. " \
             "You can also visit https://service.example.com for scheduling."

      result = response_validator.validate(text, driving_state: :highway)

      expect(result[:violations]).to include(:phone_number_while_driving)
      expect(result[:violations]).to include(:url_while_driving)
      expect(result[:violations]).to include(:response_too_long)
      expect(result[:modified_text]).not_to include("800-555-1234")
      expect(result[:modified_text]).not_to include("https://service.example.com")
    end
  end
end
