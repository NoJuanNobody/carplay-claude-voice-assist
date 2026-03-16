# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Vehicles", type: :request do
  let(:mock_redis) { instance_double(Redis) }
  let(:user) { create(:user) }
  let(:token) { jwt_token_for(user) }
  let(:headers) { auth_headers(token) }

  before do
    stub_const("REDIS", mock_redis)
    allow(mock_redis).to receive(:setex)
    allow(mock_redis).to receive(:get).and_return(nil)
    allow(mock_redis).to receive(:del)
    allow(mock_redis).to receive(:exists?).and_return(false)
  end

  describe "GET /api/v1/vehicles" do
    it "returns user's vehicles" do
      create(:vehicle, user: user, make: "Tesla", model: "Model 3")
      create(:vehicle, user: user, make: "BMW", model: "i4")

      get "/api/v1/vehicles", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["vehicles"].length).to eq(2)
    end

    it "does not return other users' vehicles" do
      other_user = create(:user)
      create(:vehicle, user: other_user)
      create(:vehicle, user: user)

      get "/api/v1/vehicles", headers: headers

      body = JSON.parse(response.body)
      expect(body["vehicles"].length).to eq(1)
    end

    it "requires authentication" do
      get "/api/v1/vehicles"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/vehicles" do
    let(:vehicle_params) do
      {
        make: "Toyota",
        model: "Camry",
        year: 2024,
        vin: "1HGBH41JXMN109186",
        vehicle_type: "sedan"
      }
    end

    it "creates a vehicle" do
      expect {
        post "/api/v1/vehicles", params: vehicle_params, headers: headers
      }.to change(Vehicle, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["vehicle"]["make"]).to eq("Toyota")
      expect(body["vehicle"]["model"]).to eq("Camry")
      expect(body["vehicle"]["year"]).to eq(2024)
    end

    it "returns error for missing required fields" do
      post "/api/v1/vehicles", params: { make: "Toyota" }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires authentication" do
      post "/api/v1/vehicles", params: vehicle_params
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /api/v1/vehicles/:id" do
    let!(:vehicle) { create(:vehicle, user: user, make: "Tesla", model: "Model 3") }

    it "updates the vehicle" do
      put "/api/v1/vehicles/#{vehicle.id}",
          params: { make: "Tesla", model: "Model Y" },
          headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["vehicle"]["model"]).to eq("Model Y")

      vehicle.reload
      expect(vehicle.model).to eq("Model Y")
    end

    it "returns not found for other user's vehicle" do
      other_user = create(:user)
      other_vehicle = create(:vehicle, user: other_user)

      put "/api/v1/vehicles/#{other_vehicle.id}",
          params: { model: "Hacked" },
          headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      put "/api/v1/vehicles/#{vehicle.id}", params: { model: "X" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /api/v1/vehicles/:id/state" do
    let!(:vehicle) { create(:vehicle, user: user) }

    it "updates vehicle state" do
      put "/api/v1/vehicles/#{vehicle.id}/state",
          params: { state: { speed: 60, fuel_level: 75, driving_mode: "drive" } },
          headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["state"]["speed"]).to eq(60)
      expect(body["state"]["fuel_level"]).to eq(75)
      expect(body["state"]["driving_mode"]).to eq("drive")
    end

    it "persists state to database" do
      put "/api/v1/vehicles/#{vehicle.id}/state",
          params: { state: { speed: 30 } },
          headers: headers

      vehicle.reload
      expect(vehicle.integration_config["last_known_state"]["speed"]).to eq(30)
    end

    it "returns not found for other user's vehicle" do
      other_user = create(:user)
      other_vehicle = create(:vehicle, user: other_user)

      put "/api/v1/vehicles/#{other_vehicle.id}/state",
          params: { state: { speed: 0 } },
          headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      put "/api/v1/vehicles/#{vehicle.id}/state",
          params: { state: { speed: 0 } }

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
