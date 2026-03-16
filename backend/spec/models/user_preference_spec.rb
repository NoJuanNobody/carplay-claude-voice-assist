require "rails_helper"

RSpec.describe UserPreference, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    it { is_expected.to validate_inclusion_of(:response_verbosity).in_array(%w[minimal concise detailed]) }

    it "validates voice_speed is within 0.5 to 2.0" do
      preference = UserPreference.new(voice_speed: 0.3)
      preference.valid?
      expect(preference.errors[:voice_speed]).to be_present

      preference.voice_speed = 2.5
      preference.valid?
      expect(preference.errors[:voice_speed]).to be_present

      preference.voice_speed = 1.0
      preference.valid?
      expect(preference.errors[:voice_speed]).to be_empty
    end
  end
end
