class Vehicle < ApplicationRecord
  belongs_to :user
  has_many :voice_sessions, dependent: :nullify

  validates :make, presence: true
  validates :model, presence: true
  validates :year, presence: true
  validates :vin, uniqueness: true, allow_nil: true
end
