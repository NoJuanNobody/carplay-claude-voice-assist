class VoiceSession < ApplicationRecord
  belongs_to :user
  belongs_to :vehicle, optional: true
  has_many :conversation_messages, dependent: :destroy
  has_many :safety_events, dependent: :nullify

  validates :session_token, presence: true, uniqueness: true
  validates :started_at, presence: true

  scope :active, -> { where(ended_at: nil) }
  scope :completed, -> { where.not(ended_at: nil) }

  before_validation :generate_session_token, on: :create

  private

  def generate_session_token
    self.session_token ||= SecureRandom.hex(32)
  end
end
