# frozen_string_literal: true

require "rails_helper"

RSpec.describe Safety::DrivingStateEvaluator do
  subject(:evaluator) { described_class.new }

  describe "#evaluate" do
    context "when vehicle is parked" do
      it "returns parked state for speed 0" do
        result = evaluator.evaluate(speed: 0)

        expect(result[:state]).to eq(:parked)
        expect(result[:restrictions]).to be_empty
      end

      it "returns parked state for speed below 3 mph" do
        result = evaluator.evaluate(speed: 2.5)

        expect(result[:state]).to eq(:parked)
      end
    end

    context "when driving in city" do
      it "returns city state for speed of 3 mph" do
        result = evaluator.evaluate(speed: 3)

        expect(result[:state]).to eq(:city)
        expect(result[:restrictions]).to include(:no_long_text)
        expect(result[:restrictions]).to include(:brevity_preferred)
      end

      it "returns city state for speed of 30 mph" do
        result = evaluator.evaluate(speed: 30)

        expect(result[:state]).to eq(:city)
      end

      it "returns city state for speed of 45 mph" do
        result = evaluator.evaluate(speed: 45)

        expect(result[:state]).to eq(:city)
      end
    end

    context "when driving on highway" do
      it "returns highway state for speed above 45 mph" do
        result = evaluator.evaluate(speed: 70)

        expect(result[:state]).to eq(:highway)
        expect(result[:restrictions]).to include(:no_long_text)
        expect(result[:restrictions]).to include(:no_visual_content)
        expect(result[:restrictions]).to include(:voice_only)
      end

      it "returns highway state for speed just over 45 mph" do
        result = evaluator.evaluate(speed: 45.1)

        expect(result[:state]).to eq(:highway)
      end
    end

    context "when emergency indicators are present" do
      it "returns emergency state regardless of speed" do
        result = evaluator.evaluate(speed: 0, emergency_indicators: true)

        expect(result[:state]).to eq(:emergency)
        expect(result[:restrictions]).to eq([:emergency_only])
      end

      it "returns emergency state at highway speed" do
        result = evaluator.evaluate(speed: 70, emergency_indicators: true)

        expect(result[:state]).to eq(:emergency)
      end
    end

    context "confidence scoring" do
      it "returns high confidence with speed, location, and driving mode" do
        result = evaluator.evaluate(
          speed: 30,
          location: { lat: 40.7, lng: -74.0 },
          driving_mode: "drive"
        )

        expect(result[:confidence]).to eq(1.0)
      end

      it "returns base confidence with only speed" do
        result = evaluator.evaluate(speed: 30)

        expect(result[:confidence]).to eq(0.6)
      end

      it "returns partial confidence with speed and location" do
        result = evaluator.evaluate(speed: 30, location: { lat: 40.7 })

        expect(result[:confidence]).to eq(0.8)
      end

      it "returns zero confidence when speed is missing" do
        result = evaluator.evaluate({})

        expect(result[:confidence]).to eq(0.0)
      end
    end
  end
end
