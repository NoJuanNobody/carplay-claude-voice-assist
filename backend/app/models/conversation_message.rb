class ConversationMessage < ApplicationRecord
  belongs_to :voice_session

  validates :role, presence: true, inclusion: { in: %w[user assistant system tool] }
  validates :content, presence: true
end
