require "rails_helper"

RSpec.describe SafetyEvent, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:voice_session).optional }
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:severity) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:severity).with_values(low: "low", medium: "medium", high: "high", critical: "critical") }
  end
end
