# frozen_string_literal: true

FactoryBot.define do
  factory :vehicle do
    user
    make { "Tesla" }
    model { "Model 3" }
    year { 2024 }
    vin { SecureRandom.alphanumeric(17).upcase }
    vehicle_type { "sedan" }
    integration_config { {} }
  end
end
