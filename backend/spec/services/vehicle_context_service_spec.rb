# frozen_string_literal: true

require "rails_helper"

RSpec.describe VehicleContextService do
  let(:mock_redis) { instance_double(Redis) }
  let(:user) { create(:user) }
  let(:vehicle) { create(:vehicle, user: user, integration_config: {}) }
  let(:service) { described_class.new }

  before do
    stub_const("REDIS", mock_redis)
    allow(mock_redis).to receive(:setex)
    allow(mock_redis).to receive(:get).and_return(nil)
    allow(mock_redis).to receive(:del)
  end

  describe "#get_state" do
    it "returns cached state when available" do
      cached_state = { "speed" => 65, "fuel_level" => 80 }
      allow(mock_redis).to receive(:get)
        .with("carplay:vehicle:#{vehicle.id}")
        .and_return(cached_state.to_json)

      state = service.get_state(vehicle.id)
      expect(state["speed"]).to eq(65)
      expect(state["fuel_level"]).to eq(80)
    end

    it "returns default state merged with last known state on cache miss" do
      vehicle.update!(integration_config: {
        "last_known_state" => { "speed" => 0, "fuel_level" => 50 }
      })

      state = service.get_state(vehicle.id)

      expect(state["speed"]).to eq(0)
      expect(state["fuel_level"]).to eq(50)
      expect(state["driving_mode"]).to eq("park")
      expect(state["connected_devices"]).to eq([])
    end

    it "caches the state on cache miss" do
      service.get_state(vehicle.id)

      expect(mock_redis).to have_received(:setex).with(
        "carplay:vehicle:#{vehicle.id}",
        300,
        anything
      )
    end

    it "returns nil for non-existent vehicle" do
      state = service.get_state(SecureRandom.uuid)
      expect(state).to be_nil
    end
  end

  describe "#update_state" do
    it "merges new state data with existing state" do
      state = service.update_state(vehicle.id, { speed: 60, fuel_level: 75 })

      expect(state["speed"]).to eq(60)
      expect(state["fuel_level"]).to eq(75)
      expect(state["driving_mode"]).to eq("park")
      expect(state["updated_at"]).to be_present
    end

    it "caches the updated state" do
      service.update_state(vehicle.id, { speed: 30 })

      expect(mock_redis).to have_received(:setex).with(
        "carplay:vehicle:#{vehicle.id}",
        300,
        anything
      ).at_least(:once)
    end

    it "persists state to vehicle integration_config" do
      service.update_state(vehicle.id, { speed: 45 })
      vehicle.reload

      expect(vehicle.integration_config["last_known_state"]["speed"]).to eq(45)
    end

    it "raises error for non-existent vehicle" do
      expect {
        service.update_state(SecureRandom.uuid, { speed: 0 })
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "preserves existing state fields not in update" do
      service.update_state(vehicle.id, { speed: 60, fuel_level: 80 })
      state = service.update_state(vehicle.id, { speed: 0 })

      expect(state["speed"]).to eq(0)
      expect(state["fuel_level"]).to eq(80)
    end
  end
end
