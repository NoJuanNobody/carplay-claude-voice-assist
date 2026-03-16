require "rails_helper"

RSpec.describe SystemHealthSnapshot, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:service_name) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:recorded_at) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(healthy: "healthy", degraded: "degraded", unhealthy: "unhealthy") }
  end
end
