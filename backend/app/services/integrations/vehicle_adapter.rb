# frozen_string_literal: true

module Integrations
  class VehicleAdapter < BaseAdapter
    DEFAULT_TIMEOUT = 5

    SUPPORTED_ACTIONS = %w[get_vehicle_status].freeze

    INFO_TYPES = %w[fuel battery range tire_pressure oil mileage all].freeze

    def execute(input, user:)
      with_timeout do
        info_type = fetch_input(input, :info_type, "all")

        unless INFO_TYPES.include?(info_type)
          return error_result("Invalid info_type '#{info_type}'. Valid types: #{INFO_TYPES.join(', ')}")
        end

        log_execution(:get_vehicle_status, info_type: info_type, user_id: user.id)

        vehicle = user.vehicles.order(created_at: :desc).first

        unless vehicle
          return error_result("No vehicle found for user. Please register a vehicle first.")
        end

        vehicle_service = VehicleContextService.new
        state = vehicle_service.get_state(vehicle.id)

        if state.nil?
          return error_result("Unable to retrieve vehicle status. The vehicle may be offline.")
        end

        status = build_status(vehicle, state, info_type)
        success_result(status)
      end
    end

    private

    def build_status(vehicle, state, info_type)
      base = {
        vehicle: "#{vehicle.year} #{vehicle.make} #{vehicle.model}",
        vehicle_id: vehicle.id,
        retrieved_at: Time.current.iso8601
      }

      case info_type
      when "all"
        base.merge(full_status(state))
      when "fuel"
        base.merge(fuel_level: state["fuel_level"], fuel_range_miles: state["fuel_range_miles"])
      when "battery"
        base.merge(battery_level: state["battery_level"], charging: state["charging"])
      when "range"
        base.merge(
          fuel_range_miles: state["fuel_range_miles"],
          battery_range_miles: state["battery_range_miles"],
          total_range_miles: state["total_range_miles"]
        )
      when "tire_pressure"
        base.merge(tire_pressure: state["tire_pressure"] || default_tire_pressure)
      when "oil"
        base.merge(oil_life_percent: state["oil_life_percent"] || 75, oil_change_due_miles: state["oil_change_due_miles"] || 2500)
      when "mileage"
        base.merge(odometer_miles: state["odometer_miles"] || 25_432, trip_miles: state["trip_miles"] || 42.7)
      end
    end

    def full_status(state)
      {
        speed: state["speed"] || 0,
        fuel_level: state["fuel_level"],
        battery_level: state["battery_level"],
        driving_mode: state["driving_mode"] || "park",
        location: state["location"],
        tire_pressure: state["tire_pressure"] || default_tire_pressure,
        oil_life_percent: state["oil_life_percent"] || 75,
        odometer_miles: state["odometer_miles"] || 25_432,
        connected_devices: state["connected_devices"] || []
      }
    end

    def default_tire_pressure
      { front_left: 35, front_right: 35, rear_left: 33, rear_right: 33 }
    end
  end
end
