# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfileService do
  let(:cache_service) { instance_double(CacheService) }
  let(:service) { described_class.new(cache_service: cache_service) }
  let(:user) { create(:user) }

  before do
    allow(cache_service).to receive(:get_profile).and_return(nil)
    allow(cache_service).to receive(:set_profile)
    allow(cache_service).to receive(:delete)
  end

  describe "#create_profile" do
    let(:params) do
      {
        first_name: "Alice",
        last_name: "Smith",
        voice_speed: 1.2,
        voice_name: "daniel",
        language: "en-GB",
        response_verbosity: "detailed",
        safety_level: "strict"
      }
    end

    it "creates user preference and updates user name" do
      result = service.create_profile(user, params)

      expect(result["first_name"]).to eq("Alice")
      expect(result["last_name"]).to eq("Smith")
      expect(result["preferences"]["voice_speed"]).to eq(1.2)
      expect(result["preferences"]["voice_name"]).to eq("daniel")
      expect(result["preferences"]["language"]).to eq("en-GB")
      expect(result["preferences"]["response_verbosity"]).to eq("detailed")
      expect(result["preferences"]["safety_level"]).to eq("strict")
    end

    it "invalidates the cache" do
      service.create_profile(user, params)
      expect(cache_service).to have_received(:delete).with("profile:#{user.id}")
    end

    it "persists the user preference to the database" do
      service.create_profile(user, params)

      user.reload
      expect(user.first_name).to eq("Alice")
      expect(user.user_preference).to be_present
      expect(user.user_preference.voice_speed).to eq(1.2)
    end

    context "with invalid preference params" do
      let(:params) { { voice_speed: 5.0 } }

      it "raises a ValidationError" do
        expect { service.create_profile(user, params) }
          .to raise_error(ProfileService::ValidationError)
      end
    end
  end

  describe "#update_profile" do
    let!(:preference) { create(:user_preference, user: user) }

    it "updates user-level attributes" do
      result = service.update_profile(user, { first_name: "Updated" })
      expect(result["first_name"]).to eq("Updated")
    end

    it "updates preference-level attributes" do
      result = service.update_profile(user, { voice_speed: 1.5 })
      expect(result["preferences"]["voice_speed"]).to eq(1.5)
    end

    it "creates preference if none exists" do
      user_without_pref = create(:user)
      result = service.update_profile(user_without_pref, { voice_speed: 0.8, response_verbosity: "minimal" })
      expect(result["preferences"]["voice_speed"]).to eq(0.8)
    end

    it "invalidates the cache after update" do
      service.update_profile(user, { first_name: "New" })
      expect(cache_service).to have_received(:delete).with("profile:#{user.id}")
    end
  end

  describe "#get_profile" do
    let!(:preference) { create(:user_preference, user: user) }

    it "returns cached profile when available" do
      cached_data = { "id" => user.id, "email" => user.email }
      allow(cache_service).to receive(:get_profile).with(user.id).and_return(cached_data)

      result = service.get_profile(user)
      expect(result).to eq(cached_data)
    end

    it "builds and caches profile when cache misses" do
      result = service.get_profile(user)

      expect(result["id"]).to eq(user.id)
      expect(result["email"]).to eq(user.email)
      expect(result["preferences"]).to be_present
      expect(cache_service).to have_received(:set_profile).with(user.id, result)
    end

    it "includes has_voice_signature field" do
      result = service.get_profile(user)
      expect(result["has_voice_signature"]).to eq(false)
    end
  end

  describe "#delete_profile" do
    let!(:preference) { create(:user_preference, user: user) }

    before { user.update!(first_name: "Alice", last_name: "Smith") }

    it "clears personal data from user" do
      service.delete_profile(user)

      user.reload
      expect(user.first_name).to be_nil
      expect(user.last_name).to be_nil
      expect(user.voice_signature_data).to be_nil
    end

    it "destroys user preference" do
      expect { service.delete_profile(user) }
        .to change { UserPreference.count }.by(-1)
    end

    it "invalidates the cache" do
      service.delete_profile(user)
      expect(cache_service).to have_received(:delete).with("profile:#{user.id}")
    end

    it "returns true on success" do
      expect(service.delete_profile(user)).to be true
    end
  end
end
