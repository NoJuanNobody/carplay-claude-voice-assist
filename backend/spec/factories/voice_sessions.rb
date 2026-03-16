# frozen_string_literal: true

FactoryBot.define do
  factory :voice_session do
    user
    vehicle { nil }
    session_token { SecureRandom.hex(32) }
    started_at { Time.current }
    ended_at { nil }
    driving_state { "unknown" }
    metadata { {} }

    trait :with_vehicle do
      association :vehicle
    end

    trait :ended do
      ended_at { Time.current }
    end
  end
end
