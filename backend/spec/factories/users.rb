# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    email { Faker::Internet.unique.email }
    password { "password123" }
    password_confirmation { "password123" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    jti { SecureRandom.uuid }

    trait :with_preference do
      after(:create) do |user|
        create(:user_preference, user: user)
      end
    end

    trait :with_voice_signature do
      voice_signature_data do
        embeddings = Array.new(128) { rand(-1.0..1.0) }
        magnitude = Math.sqrt(embeddings.sum { |e| e**2 })
        normalized = embeddings.map { |e| (e / magnitude).round(8) }

        {
          "embeddings" => normalized,
          "enrolled_at" => Time.current.iso8601,
          "embedding_version" => "v1",
          "sample_count" => 3
        }
      end
    end
  end
end
