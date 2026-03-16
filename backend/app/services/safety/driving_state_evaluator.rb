# frozen_string_literal: true

module Safety
  class DrivingStateEvaluator
    # Speed thresholds in mph
    PARKED_MAX_SPEED = 3.0
    CITY_MAX_SPEED = 45.0

    RESTRICTIONS = {
      parked: [].freeze,
      city: %i[no_long_text brevity_preferred].freeze,
      highway: %i[no_long_text no_visual_content voice_only].freeze,
      emergency: %i[emergency_only].freeze
    }.freeze

    # Evaluates the driving state from vehicle context.
    #
    # @param vehicle_state [Hash] must include :speed (in mph). May include
    #   :location, :driving_mode, :emergency_indicators.
    # @return [Hash] { state:, confidence:, restrictions: [] }
    def evaluate(vehicle_state)
      speed = vehicle_state[:speed].to_f
      emergency = vehicle_state[:emergency_indicators]

      state = infer_state(speed, emergency)
      confidence = calculate_confidence(vehicle_state)

      {
        state: state,
        confidence: confidence,
        restrictions: RESTRICTIONS.fetch(state, [])
      }
    end

    private

    def infer_state(speed, emergency)
      return :emergency if emergency.present?

      if speed < PARKED_MAX_SPEED
        :parked
      elsif speed <= CITY_MAX_SPEED
        :city
      else
        :highway
      end
    end

    def calculate_confidence(vehicle_state)
      score = 0.0

      # Speed present and non-negative => high base confidence
      if vehicle_state.key?(:speed) && vehicle_state[:speed].to_f >= 0
        score += 0.6
      end

      # Location data increases confidence
      score += 0.2 if vehicle_state[:location].present?

      # Driving mode confirmation
      score += 0.2 if vehicle_state[:driving_mode].present?

      score.clamp(0.0, 1.0).round(2)
    end
  end
end
