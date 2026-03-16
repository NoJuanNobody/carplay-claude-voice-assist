# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Sessions", type: :request do
  let(:mock_redis) { instance_double(Redis) }
  let(:user) { create(:user, :with_preference) }
  let(:vehicle) { create(:vehicle, user: user) }
  let(:token) { jwt_token_for(user) }
  let(:headers) { auth_headers(token) }

  before do
    stub_const("REDIS", mock_redis)
    allow(mock_redis).to receive(:setex)
    allow(mock_redis).to receive(:get).and_return(nil)
    allow(mock_redis).to receive(:del)
    allow(mock_redis).to receive(:exists?).and_return(false)
  end

  describe "POST /api/v1/sessions" do
    it "creates a new voice session" do
      post "/api/v1/sessions", headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["session"]["session_id"]).to be_present
      expect(body["session"]["session_token"]).to be_present
      expect(body["session"]["started_at"]).to be_present
    end

    it "creates a session with vehicle" do
      post "/api/v1/sessions", params: { vehicle_id: vehicle.id }, headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      session = VoiceSession.find(body["session"]["session_id"])
      expect(session.vehicle).to eq(vehicle)
    end

    it "returns not found for invalid vehicle" do
      post "/api/v1/sessions", params: { vehicle_id: SecureRandom.uuid }, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      post "/api/v1/sessions"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/sessions/:id" do
    let!(:session) { create(:voice_session, user: user) }

    it "ends the session" do
      delete "/api/v1/sessions/#{session.id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["session"]["ended_at"]).to be_present

      session.reload
      expect(session.ended_at).to be_present
    end

    it "returns not found for other user's session" do
      other_user = create(:user)
      other_session = create(:voice_session, user: other_user)

      delete "/api/v1/sessions/#{other_session.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      delete "/api/v1/sessions/#{session.id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/sessions/:id/messages" do
    let!(:session) { create(:voice_session, user: user, vehicle: vehicle) }

    let(:claude_response) do
      {
        role: "assistant",
        content: "Hello! How can I help you while driving?",
        tool_calls: nil,
        stop_reason: "end_turn",
        usage: { input_tokens: 50, output_tokens: 20 }
      }
    end

    before do
      allow_any_instance_of(ClaudeClient).to receive(:chat_with_tools).and_return(claude_response)
    end

    it "sends a message and returns response" do
      post "/api/v1/sessions/#{session.id}/messages",
           params: { text: "Hello", driving_state: "parked" },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["message"]["response_text"]).to eq("Hello! How can I help you while driving?")
      expect(body["message"]["latency_ms"]).to be_a(Integer)
    end

    it "creates conversation messages" do
      expect {
        post "/api/v1/sessions/#{session.id}/messages",
             params: { text: "Hello" },
             headers: headers
      }.to change(ConversationMessage, :count).by(2)
    end

    it "returns error without text parameter" do
      post "/api/v1/sessions/#{session.id}/messages",
           params: {},
           headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it "returns error for ended session" do
      session.update!(ended_at: Time.current)

      post "/api/v1/sessions/#{session.id}/messages",
           params: { text: "Hello" },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns service unavailable on Claude API error" do
      allow_any_instance_of(ClaudeClient).to receive(:chat_with_tools)
        .and_raise(ClaudeClient::ApiError, "API down")

      post "/api/v1/sessions/#{session.id}/messages",
           params: { text: "Hello" },
           headers: headers

      expect(response).to have_http_status(:service_unavailable)
    end

    it "requires authentication" do
      post "/api/v1/sessions/#{session.id}/messages",
           params: { text: "Hello" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/sessions/:id/messages" do
    let!(:session) { create(:voice_session, user: user) }

    before do
      create(:conversation_message, voice_session: session, role: "user", content: "Hi")
      create(:conversation_message, :assistant, voice_session: session)
    end

    it "returns conversation messages" do
      get "/api/v1/sessions/#{session.id}/messages", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["messages"].length).to eq(2)
      expect(body["messages"].first["role"]).to eq("user")
      expect(body["messages"].last["role"]).to eq("assistant")
      expect(body["count"]).to eq(2)
    end

    it "returns messages in chronological order" do
      get "/api/v1/sessions/#{session.id}/messages", headers: headers

      body = JSON.parse(response.body)
      timestamps = body["messages"].map { |m| m["created_at"] }
      expect(timestamps).to eq(timestamps.sort)
    end

    it "requires authentication" do
      get "/api/v1/sessions/#{session.id}/messages"

      expect(response).to have_http_status(:unauthorized)
    end
  end

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
