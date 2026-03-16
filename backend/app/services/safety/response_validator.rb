# frozen_string_literal: true

module Safety
  class ResponseValidator
    # Maximum number of sentences allowed per driving state
    MAX_SENTENCES = {
      parked: 20,
      city: 4,
      highway: 2,
      emergency: 1
    }.freeze

    TRUNCATION_NOTICE = "I'll tell you more when you're parked."

    PHONE_NUMBER_PATTERN = /\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/
    URL_PATTERN = %r{https?://\S+|www\.\S+}i

    # Validates a Claude response against safety rules for the current driving state.
    #
    # @param response_text [String] the response to validate
    # @param driving_state [Symbol] one of :parked, :city, :highway, :emergency
    # @return [Hash] { valid:, modified_text:, violations: [] }
    def validate(response_text, driving_state:)
      driving_state = driving_state.to_sym
      violations = []
      modified_text = response_text.dup

      # Check for phone numbers while driving
      if driving_state != :parked && contains_phone_number?(modified_text)
        violations << :phone_number_while_driving
        modified_text = redact_phone_numbers(modified_text)
      end

      # Check for URLs while driving
      if driving_state != :parked && contains_url?(modified_text)
        violations << :url_while_driving
        modified_text = redact_urls(modified_text)
      end

      # Enforce sentence count limits
      max = MAX_SENTENCES.fetch(driving_state, MAX_SENTENCES[:city])
      sentences = split_sentences(modified_text)

      if sentences.length > max
        violations << :response_too_long
        modified_text = sentences.first(max).join(" ") + " " + TRUNCATION_NOTICE
      end

      {
        valid: violations.empty?,
        modified_text: modified_text,
        violations: violations
      }
    end

    private

    def contains_phone_number?(text)
      PHONE_NUMBER_PATTERN.match?(text)
    end

    def contains_url?(text)
      URL_PATTERN.match?(text)
    end

    def redact_phone_numbers(text)
      text.gsub(PHONE_NUMBER_PATTERN, "[phone number hidden while driving]")
    end

    def redact_urls(text)
      text.gsub(URL_PATTERN, "[link hidden while driving]")
    end

    def split_sentences(text)
      # Split on sentence-ending punctuation followed by whitespace or end of string
      text.scan(/[^.!?]+[.!?]+/).map(&:strip).reject(&:empty?)
    end
  end
end
