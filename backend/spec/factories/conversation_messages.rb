# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_message do
    voice_session
    role { "user" }
    content { "Hello, assistant." }
    tool_calls { nil }
    tool_results { nil }
    token_count { nil }
    latency_ms { nil }

    trait :assistant do
      role { "assistant" }
      content { "Hello! How can I help you today?" }
      token_count { 50 }
      latency_ms { 450 }
    end
  end
end
