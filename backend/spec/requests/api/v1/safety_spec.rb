# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Safety", type: :request do
  let(:user) { create(:user) }
  let(:token) { jwt_token_for(user) }
  let(:headers) { auth_headers(token) }

  describe "POST /api/v1/safety/report_event" do
    let(:event_params) do
      {
        event: {
          event_type: "response_violation",
          severity: "low",
          metadata: { violation: "response_too_long" }
        }
      }
    end

    it "creates a safety event" do
      expect {
        post "/api/v1/safety/report_event", params: event_params, headers: headers
      }.to change(SafetyEvent, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["event"]["event_type"]).to eq("response_violation")
      expect(body["event"]["severity"]).to eq("low")
    end

    it "creates event with voice session" do
      session = create(:voice_session, user: user)
      params = {
        event: {
          event_type: "emergency_crash_detected",
          severity: "critical",
          voice_session_id: session.id
        }
      }

      post "/api/v1/safety/report_event", params: params, headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["event"]["voice_session_id"]).to eq(session.id)
    end

    it "returns error for missing event_type" do
      post "/api/v1/safety/report_event",
           params: { event: { severity: "low" } },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires authentication" do
      post "/api/v1/safety/report_event", params: event_params
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/safety/events" do
    before do
      create(:safety_event, user: user, event_type: "violation_a", severity: "low")
      create(:safety_event, user: user, event_type: "violation_b", severity: "high")
      create(:safety_event, user: user, event_type: "violation_c", severity: "low")
    end

    it "returns user's safety events" do
      get "/api/v1/safety/events", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["events"].length).to eq(3)
    end

    it "filters by severity" do
      get "/api/v1/safety/events", params: { severity: "high" }, headers: headers

      body = JSON.parse(response.body)
      expect(body["events"].length).to eq(1)
      expect(body["events"].first["severity"]).to eq("high")
    end

    it "respects limit parameter" do
      get "/api/v1/safety/events", params: { limit: 2 }, headers: headers

      body = JSON.parse(response.body)
      expect(body["events"].length).to eq(2)
    end

    it "does not return other users' events" do
      other_user = create(:user)
      create(:safety_event, user: other_user, event_type: "other")

      get "/api/v1/safety/events", headers: headers

      body = JSON.parse(response.body)
      expect(body["events"].length).to eq(3)
    end

    it "requires authentication" do
      get "/api/v1/safety/events"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/safety/emergency" do
    it "detects crash emergency" do
      post "/api/v1/safety/emergency",
           params: { text: "I just crashed my car", driving_state: "city" },
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["emergency"]).to be true
      expect(body["type"]).to eq("crash_detected")
      expect(body["action"]).to eq("call_911")
      expect(body["message"]).to include("911")
    end

    it "detects medical emergency" do
      post "/api/v1/safety/emergency",
           params: { text: "I think I'm having a heart attack", driving_state: "city" },
           headers: headers

      body = JSON.parse(response.body)
      expect(body["emergency"]).to be true
      expect(body["type"]).to eq("medical_emergency")
    end

    it "returns non-emergency for normal text" do
      post "/api/v1/safety/emergency",
           params: { text: "What's the weather like?", driving_state: "city" },
           headers: headers

      body = JSON.parse(response.body)
      expect(body["emergency"]).to be false
    end

    it "creates a safety event for emergencies" do
      expect {
        post "/api/v1/safety/emergency",
             params: { text: "I crashed", driving_state: "city" },
             headers: headers
      }.to change(SafetyEvent, :count).by(1)
    end

    it "does not create a safety event for non-emergencies" do
      expect {
        post "/api/v1/safety/emergency",
             params: { text: "Hello there", driving_state: "city" },
             headers: headers
      }.not_to change(SafetyEvent, :count)
    end

    it "requires authentication" do
      post "/api/v1/safety/emergency",
           params: { text: "crash", driving_state: "city" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  private

  def jwt_token_for(user)
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

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
