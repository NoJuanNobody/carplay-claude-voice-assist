# frozen_string_literal: true

module Integrations
  class MapsAdapter < BaseAdapter
    DEFAULT_TIMEOUT = 15

    SUPPORTED_ACTIONS = %w[navigate_to].freeze

    def execute(input, user:)
      with_timeout do
        validate_required!(input, :destination)

        destination = fetch_input(input, :destination)
        avoid_highways = fetch_input(input, :avoid_highways, false)
        avoid_tolls = fetch_input(input, :avoid_tolls, false)

        log_execution(:navigate_to, destination: destination, user_id: user.id)

        navigate_to(destination, avoid_highways: avoid_highways, avoid_tolls: avoid_tolls, user: user)
      end
    end

    private

    def navigate_to(destination, avoid_highways:, avoid_tolls:, user:)
      # Simulates Apple Maps / MapKit integration
      # In production, this would interface with MapKit JS or the iOS companion app
      # via a push notification or WebSocket to trigger native navigation

      route = simulate_route_calculation(destination, avoid_highways: avoid_highways, avoid_tolls: avoid_tolls)

      if route[:found]
        success_result(
          destination: destination,
          formatted_address: route[:formatted_address],
          estimated_travel_time_minutes: route[:eta_minutes],
          distance_miles: route[:distance_miles],
          route_summary: route[:summary],
          navigation_started: true,
          avoid_highways: avoid_highways,
          avoid_tolls: avoid_tolls
        )
      else
        error_result("Could not find a route to '#{destination}'. Please try a more specific address.")
      end
    end

    def simulate_route_calculation(destination, avoid_highways:, avoid_tolls:)
      # Simulated route data - in production, MapKit would provide real data
      normalized = destination.downcase.strip

      if normalized.blank?
        return { found: false }
      end

      base_eta = 15 + (normalized.length % 45)
      base_eta += 10 if avoid_highways
      distance = (base_eta * 0.8).round(1)

      {
        found: true,
        formatted_address: destination.titleize,
        eta_minutes: base_eta,
        distance_miles: distance,
        summary: avoid_highways ? "Via local roads" : "Via fastest route"
      }
    end
  end
end
