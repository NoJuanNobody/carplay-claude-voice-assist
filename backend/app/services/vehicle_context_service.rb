# frozen_string_literal: true

class VehicleContextService
  DEFAULT_STATE = {
    "speed" => 0,
    "location" => nil,
    "fuel_level" => nil,
    "battery_level" => nil,
    "driving_mode" => "park",
    "connected_devices" => []
  }.freeze

  def initialize
    @cache = CacheService.new
  end

  def get_state(vehicle_id)
    cached = @cache.get_vehicle_state(vehicle_id)
    return cached if cached

    vehicle = Vehicle.find_by(id: vehicle_id)
    return nil unless vehicle

    state = DEFAULT_STATE.merge(vehicle.integration_config.fetch("last_known_state", {}))
    @cache.set_vehicle_state(vehicle_id, state)
    state
  end

  def update_state(vehicle_id, state_data)
    vehicle = Vehicle.find(vehicle_id)

    current_state = get_state(vehicle_id) || DEFAULT_STATE.dup
    merged_state = current_state.merge(state_data.stringify_keys)
    merged_state["updated_at"] = Time.current.iso8601

    @cache.set_vehicle_state(vehicle_id, merged_state)

    config = vehicle.integration_config || {}
    config["last_known_state"] = merged_state
    vehicle.update!(integration_config: config)

    merged_state
  end
end
