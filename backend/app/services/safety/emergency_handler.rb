# frozen_string_literal: true

module Safety
  class EmergencyHandler
    EMERGENCY_KEYWORDS = {
      crash_detected: %w[crash crashed accident collision hit wreck totaled].freeze,
      medical_emergency: %w[heart\ attack stroke seizure choking unconscious bleeding can't\ breathe not\ breathing chest\ pain].freeze,
      roadside_assistance: %w[flat\ tire broke\ down tow\ truck overheating stalled won't\ start dead\ battery locked\ out].freeze,
      sos: %w[help\ me emergency sos danger].freeze
    }.freeze

    EMERGENCY_ACTIONS = {
      crash_detected: :call_911,
      medical_emergency: :call_911,
      roadside_assistance: :call_roadside,
      sos: :call_911
    }.freeze

    EMERGENCY_SEVERITIES = {
      crash_detected: :critical,
      medical_emergency: :critical,
      roadside_assistance: :high,
      sos: :critical
    }.freeze

    # Checks user input for emergency situations.
    #
    # @param text [String] the user's spoken or typed input
    # @param driving_state [Symbol] current driving state
    # @param user [User, nil] optional user for logging
    # @param voice_session [VoiceSession, nil] optional session for logging
    # @return [Hash] { emergency:, type:, action: }
    def check(text, driving_state:, user: nil, voice_session: nil)
      normalized = text.downcase.strip
      detected_type = detect_emergency_type(normalized)

      unless detected_type
        return { emergency: false, type: nil, action: nil }
      end

      action = EMERGENCY_ACTIONS[detected_type]

      # Escalate roadside to 911 if at highway speed
      if detected_type == :roadside_assistance && driving_state.to_sym == :highway
        action = :call_911
      end

      log_emergency_event(detected_type, action, user: user, voice_session: voice_session)

      {
        emergency: true,
        type: detected_type,
        action: action
      }
    end

    private

    def detect_emergency_type(text)
      EMERGENCY_KEYWORDS.each do |type, keywords|
        return type if keywords.any? { |kw| text.include?(kw) }
      end

      nil
    end

    def log_emergency_event(type, action, user:, voice_session:)
      return unless user

      SafetyEvent.create!(
        user: user,
        voice_session: voice_session,
        event_type: "emergency_#{type}",
        severity: EMERGENCY_SEVERITIES.fetch(type, :critical),
        metadata: {
          emergency_type: type,
          action: action,
          detected_at: Time.current.iso8601
        }
      )
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("Failed to log emergency event: #{e.message}")
    end
  end
end
