# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Profiles", type: :request do
  let(:user) { create(:user, :with_preference, first_name: "Alice", last_name: "Smith") }
  let(:token) { jwt_token_for(user) }
  let(:headers) { auth_headers(token) }

  before do
    allow_any_instance_of(CacheService).to receive(:get_profile).and_return(nil)
    allow_any_instance_of(CacheService).to receive(:set_profile)
    allow_any_instance_of(CacheService).to receive(:delete)
  end

  describe "GET /api/v1/profile" do
    it "returns the current user profile" do
      get "/api/v1/profile", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["profile"]["email"]).to eq(user.email)
      expect(body["profile"]["first_name"]).to eq("Alice")
      expect(body["profile"]["preferences"]).to be_present
    end

    it "requires authentication" do
      get "/api/v1/profile"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /api/v1/profile" do
    it "updates user profile attributes" do
      put "/api/v1/profile", params: { first_name: "Bob", voice_speed: 1.5 }, headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["profile"]["first_name"]).to eq("Bob")
      expect(body["profile"]["preferences"]["voice_speed"]).to eq(1.5)
    end

    it "returns error for invalid voice_speed" do
      put "/api/v1/profile", params: { voice_speed: 5.0 }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires authentication" do
      put "/api/v1/profile", params: { first_name: "Hacker" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/profile/voice_signature" do
    let(:embeddings) { Array.new(128) { rand(-1.0..1.0) } }

    it "enrolls a voice signature" do
      post "/api/v1/profile/voice_signature",
           params: { embeddings: embeddings, samples: 3 },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["voice_signature"]["enrolled"]).to be true
    end

    it "returns error for missing embeddings" do
      post "/api/v1/profile/voice_signature",
           params: {},
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires authentication" do
      post "/api/v1/profile/voice_signature", params: { embeddings: embeddings }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/profile/voice_signature" do
    it "removes a voice signature" do
      user.update!(voice_signature_data: {
        "embeddings" => Array.new(128) { 0.01 },
        "enrolled_at" => Time.current.iso8601,
        "embedding_version" => "v1",
        "sample_count" => 1
      })

      delete "/api/v1/profile/voice_signature", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["voice_signature"]["deleted"]).to be true
    end

    it "returns error when no signature exists" do
      delete "/api/v1/profile/voice_signature", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires authentication" do
      delete "/api/v1/profile/voice_signature"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # Helper methods
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
