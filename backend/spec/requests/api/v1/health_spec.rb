# frozen_string_literal: true

require "rails_helper"
require "metrics/collector"

RSpec.describe "Api::V1::Health", type: :request do
  let(:user) { create(:user) }
  let(:token) do
    secret = Rails.application.credentials.devise_jwt_secret_key ||
             ENV.fetch("DEVISE_JWT_SECRET_KEY", "test-secret-key")
    payload = {
      sub: user.id,
      jti: user.jti,
      iat: Time.current.to_i,
      exp: 24.hours.from_now.to_i
    }
    JWT.encode(payload, secret, "HS256")
  end
  let(:auth_headers) { { "Authorization" => "Bearer #{token}" } }

  before do
    Metrics::Collector.instance.reset!
  end

  describe "GET /api/v1/health" do
    it "returns ok without authentication" do
      get "/api/v1/health"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("ok")
      expect(body["timestamp"]).to be_present
      expect(body["version"]).to be_present
    end

    it "includes the app version" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("APP_VERSION", "1.0.0").and_return("2.5.0")

      get "/api/v1/health"

      body = JSON.parse(response.body)
      expect(body["version"]).to eq("2.5.0")
    end
  end

  describe "GET /api/v1/health/detailed" do
    it "returns unauthorized without a token" do
      get "/api/v1/health/detailed"

      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      let(:service_results) do
        {
          postgres: { status: "healthy", latency_ms: 2 },
          redis: { status: "healthy", latency_ms: 1 },
          claude_api: { status: "healthy", latency_ms: 150 }
        }
      end

      before do
        health_service = instance_double(HealthCheckService)
        allow(HealthCheckService).to receive(:new).and_return(health_service)
        allow(health_service).to receive(:check_all).and_return(service_results)
        allow(health_service).to receive(:overall_status).with(service_results).and_return("healthy")
      end

      it "returns detailed health with service statuses" do
        get "/api/v1/health/detailed", headers: auth_headers

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("healthy")
        expect(body["services"]["postgres"]["status"]).to eq("healthy")
        expect(body["services"]["redis"]["status"]).to eq("healthy")
        expect(body["services"]["claude_api"]["status"]).to eq("healthy")
      end

      it "returns metrics in the response" do
        get "/api/v1/health/detailed", headers: auth_headers

        body = JSON.parse(response.body)
        expect(body["metrics"]).to include(
          "requests_total",
          "avg_response_ms",
          "error_rate",
          "active_sessions"
        )
      end

      context "when a service is unhealthy" do
        before do
          unhealthy_results = service_results.merge(
            redis: { status: "unhealthy", latency_ms: 0, error: "Connection refused" }
          )
          health_service = instance_double(HealthCheckService)
          allow(HealthCheckService).to receive(:new).and_return(health_service)
          allow(health_service).to receive(:check_all).and_return(unhealthy_results)
          allow(health_service).to receive(:overall_status).with(unhealthy_results).and_return("unhealthy")
        end

        it "returns 503 service unavailable" do
          get "/api/v1/health/detailed", headers: auth_headers

          expect(response).to have_http_status(:service_unavailable)
          body = JSON.parse(response.body)
          expect(body["status"]).to eq("unhealthy")
        end
      end
    end
  end

  describe "GET /api/v1/health/metrics" do
    it "returns unauthorized without a token" do
      get "/api/v1/health/metrics"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the metrics snapshot when authenticated" do
      Metrics::Collector.instance.record_request("/api/v1/sessions", "POST", 200, 45)
      Metrics::Collector.instance.record_request("/api/v1/sessions", "POST", 500, 120)

      get "/api/v1/health/metrics", headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["requests_total"]).to eq(2)
      expect(body["errors_total"]).to eq(1)
      expect(body["avg_response_ms"]).to eq(82.5)
      expect(body["error_rate"]).to eq(50.0)
    end
  end
end
