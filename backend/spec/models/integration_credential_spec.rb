require "rails_helper"

RSpec.describe IntegrationCredential, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:service_name) }
  end

  describe "scopes" do
    it "defines an active scope" do
      expect(IntegrationCredential).to respond_to(:active)
    end
  end
end
