# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::MapsAdapter do
  let(:adapter) { described_class.new }
  let(:user) { create(:user) }

  describe "#execute" do
    context "with a valid destination" do
      it "returns navigation data" do
        result = adapter.execute({ "destination" => "123 Main Street" }, user: user)

        expect(result.success).to be true
        expect(result.data[:destination]).to eq("123 Main Street")
        expect(result.data[:formatted_address]).to eq("123 Main Street")
        expect(result.data[:estimated_travel_time_minutes]).to be_a(Integer)
        expect(result.data[:distance_miles]).to be_a(Float)
        expect(result.data[:navigation_started]).to be true
      end

      it "respects avoid_highways option" do
        result_normal = adapter.execute({ "destination" => "Airport" }, user: user)
        result_no_hwy = adapter.execute(
          { "destination" => "Airport", "avoid_highways" => true },
          user: user
        )

        expect(result_no_hwy.data[:avoid_highways]).to be true
        expect(result_no_hwy.data[:route_summary]).to eq("Via local roads")
        expect(result_no_hwy.data[:estimated_travel_time_minutes]).to be > result_normal.data[:estimated_travel_time_minutes]
      end

      it "respects avoid_tolls option" do
        result = adapter.execute(
          { "destination" => "Downtown", "avoid_tolls" => true },
          user: user
        )

        expect(result.success).to be true
        expect(result.data[:avoid_tolls]).to be true
      end
    end

    context "with missing destination" do
      it "raises a ValidationError" do
        expect {
          adapter.execute({}, user: user)
        }.to raise_error(Integrations::BaseAdapter::ValidationError, /Missing required fields.*destination/)
      end
    end

    context "with symbol keys in input" do
      it "handles symbol keys correctly" do
        result = adapter.execute({ destination: "Home" }, user: user)

        expect(result.success).to be true
        expect(result.data[:destination]).to eq("Home")
      end
    end
  end
end
