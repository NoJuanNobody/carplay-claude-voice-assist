class UserPreference < ApplicationRecord
  belongs_to :user

  validates :voice_speed, inclusion: { in: 0.5..2.0 }
  validates :response_verbosity, inclusion: { in: %w[minimal concise detailed] }
end
