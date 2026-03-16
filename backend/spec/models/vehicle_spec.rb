require "rails_helper"

RSpec.describe Vehicle, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:voice_sessions).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:make) }
    it { is_expected.to validate_presence_of(:model) }
    it { is_expected.to validate_presence_of(:year) }
  end
end
