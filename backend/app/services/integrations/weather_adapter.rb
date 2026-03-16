# frozen_string_literal: true

module Integrations
  class WeatherAdapter < BaseAdapter
    DEFAULT_TIMEOUT = 10

    SUPPORTED_ACTIONS = %w[get_weather].freeze

    def execute(input, user:)
      with_timeout do
        location = fetch_input(input, :location, "Current Location")
        forecast = fetch_input(input, :forecast, false)

        log_execution(:get_weather, location: location, forecast: forecast, user_id: user.id)

        # Simulates WeatherKit integration
        # In production, this would use Apple WeatherKit REST API or the iOS companion app
        weather = simulate_weather(location, forecast: forecast)

        success_result(weather)
      end
    end

    private

    def simulate_weather(location, forecast:)
      current = {
        location: location,
        temperature_f: 72,
        temperature_c: 22,
        condition: "Partly Cloudy",
        humidity: 55,
        wind_speed_mph: 8,
        wind_direction: "NW",
        uv_index: 5,
        visibility_miles: 10,
        retrieved_at: Time.current.iso8601
      }

      if forecast
        current[:forecast] = [
          { day: "Today", high_f: 75, low_f: 58, condition: "Partly Cloudy", precipitation_chance: 10 },
          { day: "Tomorrow", high_f: 78, low_f: 60, condition: "Sunny", precipitation_chance: 5 },
          { day: date_label(2), high_f: 70, low_f: 55, condition: "Rain", precipitation_chance: 80 },
          { day: date_label(3), high_f: 65, low_f: 50, condition: "Cloudy", precipitation_chance: 40 },
          { day: date_label(4), high_f: 73, low_f: 57, condition: "Sunny", precipitation_chance: 0 }
        ]
      end

      current
    end

    def date_label(days_from_now)
      (Date.current + days_from_now.days).strftime("%A")
    end
  end
end
