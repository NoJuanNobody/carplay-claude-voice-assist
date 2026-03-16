class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :jwt_authenticatable,
         jwt_revocation_strategy: self

  include Devise::JWT::RevocationStrategies::JTIMatcher

  has_many :vehicles, dependent: :destroy
  has_many :voice_sessions, dependent: :destroy
  has_many :safety_events, dependent: :destroy
  has_many :integration_credentials, dependent: :destroy
  has_one :user_preference, dependent: :destroy

  validates :email, presence: true, uniqueness: true
  validates :jti, presence: true, uniqueness: true

  before_create :generate_jti

  private

  def generate_jti
    self.jti ||= SecureRandom.uuid
  end
end
