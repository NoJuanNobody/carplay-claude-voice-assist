# frozen_string_literal: true

require "rails_helper"

RSpec.describe Safety::EmergencyHandler do
  subject(:handler) { described_class.new }

  let(:user) { create(:user) }
  let(:voice_session) { create(:voice_session, user: user) }

  describe "#check" do
    context "when no emergency is detected" do
      it "returns non-emergency result" do
        result = handler.check("What's the weather like?", driving_state: :city)

        expect(result[:emergency]).to be false
        expect(result[:type]).to be_nil
        expect(result[:action]).to be_nil
      end

      it "does not create a safety event" do
        expect {
          handler.check("Navigate to the store", driving_state: :city, user: user)
        }.not_to change(SafetyEvent, :count)
      end
    end

    context "when a crash is detected" do
      it "returns crash emergency" do
        result = handler.check("I think I just crashed", driving_state: :city)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:crash_detected)
        expect(result[:action]).to eq(:call_911)
      end

      it "detects collision keywords" do
        result = handler.check("There's been a collision", driving_state: :city)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:crash_detected)
      end

      it "logs a safety event" do
        expect {
          handler.check("I crashed", driving_state: :city, user: user, voice_session: voice_session)
        }.to change(SafetyEvent, :count).by(1)

        event = SafetyEvent.last
        expect(event.event_type).to eq("emergency_crash_detected")
        expect(event.severity).to eq("critical")
        expect(event.user).to eq(user)
        expect(event.voice_session).to eq(voice_session)
      end
    end

    context "when a medical emergency is detected" do
      it "detects heart attack" do
        result = handler.check("I think I'm having a heart attack", driving_state: :city)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:medical_emergency)
        expect(result[:action]).to eq(:call_911)
      end

      it "detects stroke" do
        result = handler.check("I think someone is having a stroke", driving_state: :city)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:medical_emergency)
      end

      it "detects breathing difficulties" do
        result = handler.check("I can't breathe", driving_state: :city)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:medical_emergency)
      end
    end

    context "when roadside assistance is needed" do
      it "detects flat tire" do
        result = handler.check("I have a flat tire", driving_state: :city)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:roadside_assistance)
        expect(result[:action]).to eq(:call_roadside)
      end

      it "detects breakdown" do
        result = handler.check("My car broke down", driving_state: :city)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:roadside_assistance)
      end

      it "escalates to 911 on highway" do
        result = handler.check("I have a flat tire", driving_state: :highway)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:roadside_assistance)
        expect(result[:action]).to eq(:call_911)
      end
    end

    context "when SOS is detected" do
      it "detects help me" do
        result = handler.check("help me please", driving_state: :city)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:sos)
        expect(result[:action]).to eq(:call_911)
      end

      it "detects emergency keyword" do
        result = handler.check("this is an emergency", driving_state: :city)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:sos)
      end
    end

    context "case insensitivity" do
      it "detects uppercase emergency keywords" do
        result = handler.check("I CRASHED MY CAR", driving_state: :city)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:crash_detected)
      end
    end

    context "when logging fails" do
      it "still returns the emergency result" do
        allow(SafetyEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

        result = handler.check("I crashed", driving_state: :city, user: user)

        expect(result[:emergency]).to be true
        expect(result[:type]).to eq(:crash_detected)
      end
    end

    context "without a user" do
      it "does not attempt to log" do
        expect {
          handler.check("I crashed", driving_state: :city)
        }.not_to change(SafetyEvent, :count)
      end
    end
  end
end
