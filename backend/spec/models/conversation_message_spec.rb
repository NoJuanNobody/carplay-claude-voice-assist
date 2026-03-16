require "rails_helper"

RSpec.describe ConversationMessage, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:voice_session) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:role) }
    it { is_expected.to validate_inclusion_of(:role).in_array(%w[user assistant system tool]) }
    it { is_expected.to validate_presence_of(:content) }
  end
end
