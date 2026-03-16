# frozen_string_literal: true

require "rails_helper"

RSpec.describe Safety::ResponseValidator do
  subject(:validator) { described_class.new }

  describe "#validate" do
    context "when parked" do
      it "allows long responses" do
        text = (["This is a sentence."] * 15).join(" ")
        result = validator.validate(text, driving_state: :parked)

        expect(result[:valid]).to be true
        expect(result[:modified_text]).to eq(text)
        expect(result[:violations]).to be_empty
      end

      it "allows phone numbers" do
        text = "Call me at 555-123-4567."
        result = validator.validate(text, driving_state: :parked)

        expect(result[:valid]).to be true
        expect(result[:modified_text]).to include("555-123-4567")
      end

      it "allows URLs" do
        text = "Visit https://example.com for details."
        result = validator.validate(text, driving_state: :parked)

        expect(result[:valid]).to be true
        expect(result[:modified_text]).to include("https://example.com")
      end
    end

    context "when in city driving" do
      it "truncates responses longer than 4 sentences" do
        text = "First sentence. Second sentence. Third sentence. Fourth sentence. Fifth sentence."
        result = validator.validate(text, driving_state: :city)

        expect(result[:valid]).to be false
        expect(result[:violations]).to include(:response_too_long)
        expect(result[:modified_text]).to include("I'll tell you more when you're parked")
        expect(result[:modified_text]).not_to include("Fifth sentence")
      end

      it "allows responses with 4 or fewer sentences" do
        text = "First sentence. Second sentence. Third sentence. Fourth sentence."
        result = validator.validate(text, driving_state: :city)

        expect(result[:violations]).not_to include(:response_too_long)
      end

      it "redacts phone numbers" do
        text = "Call 555-123-4567 now."
        result = validator.validate(text, driving_state: :city)

        expect(result[:valid]).to be false
        expect(result[:violations]).to include(:phone_number_while_driving)
        expect(result[:modified_text]).to include("[phone number hidden while driving]")
        expect(result[:modified_text]).not_to include("555-123-4567")
      end

      it "redacts URLs" do
        text = "Visit https://example.com for more."
        result = validator.validate(text, driving_state: :city)

        expect(result[:valid]).to be false
        expect(result[:violations]).to include(:url_while_driving)
        expect(result[:modified_text]).to include("[link hidden while driving]")
      end
    end

    context "when on highway" do
      it "truncates responses longer than 2 sentences" do
        text = "First sentence. Second sentence. Third sentence."
        result = validator.validate(text, driving_state: :highway)

        expect(result[:valid]).to be false
        expect(result[:violations]).to include(:response_too_long)
        expect(result[:modified_text]).to include("I'll tell you more when you're parked")
      end

      it "allows responses with 2 or fewer sentences" do
        text = "First sentence. Second sentence."
        result = validator.validate(text, driving_state: :highway)

        expect(result[:violations]).not_to include(:response_too_long)
      end

      it "redacts phone numbers" do
        text = "The number is (800) 555-1234."
        result = validator.validate(text, driving_state: :highway)

        expect(result[:violations]).to include(:phone_number_while_driving)
      end
    end

    context "when in emergency state" do
      it "truncates to 1 sentence" do
        text = "Stay calm. Help is coming. Do not move."
        result = validator.validate(text, driving_state: :emergency)

        expect(result[:violations]).to include(:response_too_long)
      end

      it "allows a single sentence" do
        text = "Emergency services have been contacted."
        result = validator.validate(text, driving_state: :emergency)

        expect(result[:violations]).not_to include(:response_too_long)
      end
    end

    context "with multiple violations" do
      it "reports all violations" do
        text = "Call 555-123-4567 or visit https://example.com for help. " \
               "Second sentence. Third sentence. Fourth sentence. Fifth sentence."
        result = validator.validate(text, driving_state: :city)

        expect(result[:valid]).to be false
        expect(result[:violations]).to include(:phone_number_while_driving)
        expect(result[:violations]).to include(:url_while_driving)
        expect(result[:violations]).to include(:response_too_long)
      end
    end

    context "with string driving state" do
      it "accepts string driving states" do
        text = "Short response."
        result = validator.validate(text, driving_state: "highway")

        expect(result[:valid]).to be true
      end
    end
  end
end
