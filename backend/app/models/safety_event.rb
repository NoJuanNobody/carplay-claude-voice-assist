class SafetyEvent < ApplicationRecord
  belongs_to :voice_session, optional: true
  belongs_to :user

  enum :severity, { low: "low", medium: "medium", high: "high", critical: "critical" }

  validates :event_type, presence: true
  validates :severity, presence: true
end
