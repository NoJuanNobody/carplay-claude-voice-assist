# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Auth", type: :request do
  let(:valid_user_params) do
    {
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123",
      first_name: "Test",
      last_name: "User"
    }
  end

  before do
    allow_any_instance_of(CacheService).to receive(:get_profile).and_return(nil)
    allow_any_instance_of(CacheService).to receive(:set_profile)
    allow_any_instance_of(CacheService).to receive(:delete)
  end

  describe "POST /api/v1/auth/register" do
    it "creates a user and returns a token" do
      post "/api/v1/auth/register", params: valid_user_params

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["token"]).to be_present
      expect(body["user"]["email"]).to eq("test@example.com")
      expect(body["user"]["first_name"]).to eq("Test")
    end

    it "creates a user preference" do
      expect {
        post "/api/v1/auth/register", params: valid_user_params
      }.to change(UserPreference, :count).by(1)
    end

    it "returns error for duplicate email" do
      create(:user, email: "test@example.com")
      post "/api/v1/auth/register", params: valid_user_params

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to be_present
    end

    it "returns error for missing password" do
      post "/api/v1/auth/register", params: { email: "test@example.com" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/auth/login" do
    let!(:user) { create(:user, email: "login@example.com", password: "password123") }

    it "authenticates with valid credentials" do
      post "/api/v1/auth/login", params: { email: "login@example.com", password: "password123" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["token"]).to be_present
      expect(body["user"]["email"]).to eq("login@example.com")
    end

    it "rejects invalid password" do
      post "/api/v1/auth/login", params: { email: "login@example.com", password: "wrong" }

      expect(response).to have_http_status(:unauthorized)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Invalid email or password")
    end

    it "rejects non-existent email" do
      post "/api/v1/auth/login", params: { email: "nobody@example.com", password: "password123" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rotates the jti on login" do
      old_jti = user.jti
      post "/api/v1/auth/login", params: { email: "login@example.com", password: "password123" }

      user.reload
      expect(user.jti).not_to eq(old_jti)
    end
  end

  describe "DELETE /api/v1/auth/logout" do
    let(:user) { create(:user) }

    it "revokes the JWT by rotating jti" do
      token = jwt_token_for(user)
      old_jti = user.jti

      delete "/api/v1/auth/logout", headers: auth_headers(token)

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.jti).not_to eq(old_jti)
    end

    it "requires authentication" do
      delete "/api/v1/auth/logout"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/auth/me" do
    let(:user) { create(:user, :with_preference) }

    it "returns current user profile" do
      token = jwt_token_for(user)
      get "/api/v1/auth/me", headers: auth_headers(token)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["user"]["id"]).to eq(user.id)
      expect(body["user"]["email"]).to eq(user.email)
    end

    it "requires authentication" do
      get "/api/v1/auth/me"

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
