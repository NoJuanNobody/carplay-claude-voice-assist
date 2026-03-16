require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:vehicles).dependent(:destroy) }
    it { is_expected.to have_many(:voice_sessions).dependent(:destroy) }
    it { is_expected.to have_many(:safety_events).dependent(:destroy) }
    it { is_expected.to have_many(:integration_credentials).dependent(:destroy) }
    it { is_expected.to have_one(:user_preference).dependent(:destroy) }
  end

  describe "validations" do
    subject { User.new(email: "test@example.com", password: "password123", jti: SecureRandom.uuid) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_presence_of(:jti) }
    it { is_expected.to validate_uniqueness_of(:jti) }
  end

  describe "callbacks" do
    it "generates a jti before create if not set" do
      user = User.new(email: "test@example.com", password: "password123")
      user.valid?
      expect(user.jti).to be_present
    end
  end
end
