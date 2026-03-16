# frozen_string_literal: true

module Api
  module V1
    class HealthController < ApplicationController
      skip_before_action :authenticate_user!, only: [:show]

      # GET /api/v1/health
      def show
        render json: {
          status: "ok",
          timestamp: Time.current.iso8601,
          version: app_version
        }, status: :ok
      end

      # GET /api/v1/health/detailed
      def detailed
        service = HealthCheckService.new
        service_results = service.check_all
        status = service.overall_status(service_results)

        metrics = Metrics::Collector.instance.snapshot

        http_status = status == "healthy" ? :ok : :service_unavailable

        render json: {
          status: status,
          timestamp: Time.current.iso8601,
          version: app_version,
          services: service_results,
          metrics: {
            requests_total: metrics[:requests_total],
            avg_response_ms: metrics[:avg_response_ms],
            error_rate: metrics[:error_rate],
            active_sessions: metrics[:active_sessions]
          }
        }, status: http_status
      end

      # GET /api/v1/health/metrics
      def metrics
        snapshot = Metrics::Collector.instance.snapshot

        render json: snapshot, status: :ok
      end

      private

      def app_version
        ENV.fetch("APP_VERSION", "1.0.0")
      end
    end
  end
end
