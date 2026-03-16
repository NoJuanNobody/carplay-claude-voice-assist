# frozen_string_literal: true

module Api
  module V1
    class SafetyController < ApplicationController
      # POST /api/v1/safety/report_event
      def report_event
        event = current_user.safety_events.build(safety_event_params)
        event.save!

        render json: { event: event_response(event) }, status: :created
      end

      # GET /api/v1/safety/events
      def events
        safety_events = current_user.safety_events
                                    .order(created_at: :desc)
                                    .limit(params.fetch(:limit, 50).to_i)

        if params[:severity].present?
          safety_events = safety_events.where(severity: params[:severity])
        end

        render json: {
          events: safety_events.map { |e| event_response(e) }
        }, status: :ok
      end

      # POST /api/v1/safety/emergency
      def emergency
        handler = Safety::EmergencyHandler.new
        session = current_user.voice_sessions.active.last

        result = handler.check(
          params.require(:text),
          driving_state: params.fetch(:driving_state, :city).to_sym,
          user: current_user,
          voice_session: session
        )

        if result[:emergency]
          render json: {
            emergency: true,
            type: result[:type],
            action: result[:action],
            message: emergency_message(result[:type], result[:action])
          }, status: :ok
        else
          render json: { emergency: false }, status: :ok
        end
      end

      private

      def safety_event_params
        params.require(:event).permit(
          :event_type, :severity, :voice_session_id, metadata: {}
        )
      end

      def event_response(event)
        {
          id: event.id,
          event_type: event.event_type,
          severity: event.severity,
          voice_session_id: event.voice_session_id,
          metadata: event.metadata,
          created_at: event.created_at.iso8601
        }
      end

      def emergency_message(type, action)
        case action
        when :call_911
          "Emergency detected: #{type.to_s.humanize}. Initiating 911 call."
        when :call_roadside
          "Roadside assistance needed. Connecting you now."
        when :alert_emergency_contact
          "Alerting your emergency contact."
        else
          "Emergency detected. Please stay safe."
        end
      end
    end
  end
end
