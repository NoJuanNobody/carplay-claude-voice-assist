# frozen_string_literal: true

FactoryBot.define do
  factory :safety_event do
    user
    voice_session { nil }
    event_type { "response_violation" }
    severity { "low" }
    metadata { {} }

    trait :with_session do
      association :voice_session
    end

    trait :critical do
      severity { "critical" }
    end

    trait :emergency do
      event_type { "emergency_crash_detected" }
      severity { "critical" }
      metadata do
        {
          emergency_type: "crash_detected",
          action: "call_911",
          detected_at: Time.current.iso8601
        }
      end
    end
  end
end
