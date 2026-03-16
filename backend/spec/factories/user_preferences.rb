# frozen_string_literal: true

FactoryBot.define do
  factory :user_preference do
    user
    voice_speed { 1.0 }
    voice_name { "samantha" }
    language { "en-US" }
    response_verbosity { "concise" }
    safety_level { "standard" }
    custom_settings { {} }
  end
end
