class IntegrationCredential < ApplicationRecord
  belongs_to :user

  validates :service_name, presence: true
  validates :service_name, uniqueness: { scope: :user_id }

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
end
