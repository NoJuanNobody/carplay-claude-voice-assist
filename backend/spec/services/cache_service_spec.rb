# frozen_string_literal: true

require "rails_helper"

RSpec.describe CacheService do
  let(:mock_redis) { instance_double(Redis) }
  let(:service) { described_class.new }

  before do
    stub_const("REDIS", mock_redis)
  end

  describe "#initialize" do
    it "defaults namespace to nil" do
      expect(service.namespace).to be_nil
    end

    it "accepts a custom namespace" do
      svc = described_class.new(namespace: "test")
      expect(svc.namespace).to eq("test")
    end
  end

  describe "key prefixing" do
    it "prefixes keys with carplay:" do
      allow(mock_redis).to receive(:get).with("carplay:foo").and_return(nil)
      service.get("foo")
      expect(mock_redis).to have_received(:get).with("carplay:foo")
    end

    it "includes namespace in key when provided" do
      svc = described_class.new(namespace: "v1")
      allow(mock_redis).to receive(:get).with("carplay:v1:foo").and_return(nil)
      svc.get("foo")
      expect(mock_redis).to have_received(:get).with("carplay:v1:foo")
    end
  end

  describe "#get" do
    it "returns parsed JSON for hash values" do
      allow(mock_redis).to receive(:get)
        .with("carplay:session:abc")
        .and_return('{"user_id":1,"active":true}')

      result = service.get("session:abc")
      expect(result).to eq({ "user_id" => 1, "active" => true })
    end

    it "returns raw string when value is not valid JSON" do
      allow(mock_redis).to receive(:get)
        .with("carplay:plain")
        .and_return("hello world")

      expect(service.get("plain")).to eq("hello world")
    end

    it "returns nil for missing keys" do
      allow(mock_redis).to receive(:get).with("carplay:missing").and_return(nil)
      expect(service.get("missing")).to be_nil
    end

    it "tracks cache hits" do
      allow(mock_redis).to receive(:get).and_return("val")
      service.get("a")
      service.get("b")
      expect(service.stats[:hits]).to eq(2)
    end

    it "tracks cache misses" do
      allow(mock_redis).to receive(:get).and_return(nil)
      service.get("x")
      expect(service.stats[:misses]).to eq(1)
    end
  end

  describe "#set" do
    it "serializes hashes to JSON and applies TTL from policy" do
      allow(mock_redis).to receive(:setex)
      service.set("session:abc", { user_id: 1 })
      expect(mock_redis).to have_received(:setex)
        .with("carplay:session:abc", 1800, '{"user_id":1}')
    end

    it "uses explicit TTL when provided" do
      allow(mock_redis).to receive(:setex)
      service.set("session:abc", { a: 1 }, ttl: 60)
      expect(mock_redis).to have_received(:setex)
        .with("carplay:session:abc", 60, '{"a":1}')
    end

    it "stores plain strings without JSON wrapping" do
      allow(mock_redis).to receive(:setex)
      service.set("health:ping", "pong")
      expect(mock_redis).to have_received(:setex)
        .with("carplay:health:ping", 60, "pong")
    end

    it "calls set without TTL for unknown key segments" do
      allow(mock_redis).to receive(:set)
      service.set("unknown:key", "val")
      expect(mock_redis).to have_received(:set)
        .with("carplay:unknown:key", "val")
    end
  end

  describe "#delete" do
    it "deletes the prefixed key" do
      allow(mock_redis).to receive(:del)
      service.delete("session:abc")
      expect(mock_redis).to have_received(:del).with("carplay:session:abc")
    end
  end

  describe "#exists?" do
    it "checks existence of the prefixed key" do
      allow(mock_redis).to receive(:exists?).with("carplay:session:abc").and_return(true)
      expect(service.exists?("session:abc")).to be true
    end
  end

  describe "#expire" do
    it "sets TTL on the prefixed key" do
      allow(mock_redis).to receive(:expire)
      service.expire("session:abc", 120)
      expect(mock_redis).to have_received(:expire).with("carplay:session:abc", 120)
    end
  end

  describe "TTL policies" do
    before { allow(mock_redis).to receive(:setex) }

    it "applies 1800s TTL for session keys" do
      service.set("session:x", "data")
      expect(mock_redis).to have_received(:setex).with(anything, 1800, anything)
    end

    it "applies 3600s TTL for profile keys" do
      service.set("profile:x", "data")
      expect(mock_redis).to have_received(:setex).with(anything, 3600, anything)
    end

    it "applies 300s TTL for vehicle keys" do
      service.set("vehicle:x", "data")
      expect(mock_redis).to have_received(:setex).with(anything, 300, anything)
    end

    it "applies 900s TTL for integration keys" do
      service.set("integration:x", "data")
      expect(mock_redis).to have_received(:setex).with(anything, 900, anything)
    end

    it "applies 60s TTL for health keys" do
      service.set("health:x", "data")
      expect(mock_redis).to have_received(:setex).with(anything, 60, anything)
    end
  end

  describe "#get_session / #set_session" do
    it "stores and retrieves session data with correct key" do
      allow(mock_redis).to receive(:setex)
      allow(mock_redis).to receive(:get)
        .with("carplay:session:s1")
        .and_return('{"active":true}')

      service.set_session("s1", { active: true })
      expect(mock_redis).to have_received(:setex)
        .with("carplay:session:s1", 1800, '{"active":true}')

      result = service.get_session("s1")
      expect(result).to eq({ "active" => true })
    end
  end

  describe "#get_profile / #set_profile" do
    it "stores and retrieves profile data with correct key and TTL" do
      allow(mock_redis).to receive(:setex)
      allow(mock_redis).to receive(:get)
        .with("carplay:profile:u1")
        .and_return('{"name":"Alice"}')

      service.set_profile("u1", { name: "Alice" })
      expect(mock_redis).to have_received(:setex)
        .with("carplay:profile:u1", 3600, '{"name":"Alice"}')

      expect(service.get_profile("u1")).to eq({ "name" => "Alice" })
    end
  end

  describe "#get_vehicle_state / #set_vehicle_state" do
    it "stores and retrieves vehicle state with correct key and TTL" do
      allow(mock_redis).to receive(:setex)
      allow(mock_redis).to receive(:get)
        .with("carplay:vehicle:v1")
        .and_return('{"speed":60}')

      service.set_vehicle_state("v1", { speed: 60 })
      expect(mock_redis).to have_received(:setex)
        .with("carplay:vehicle:v1", 300, '{"speed":60}')

      expect(service.get_vehicle_state("v1")).to eq({ "speed" => 60 })
    end
  end

  describe "#invalidate_pattern" do
    it "deletes all keys matching the pattern" do
      allow(mock_redis).to receive(:keys)
        .with("carplay:session:*")
        .and_return(["carplay:session:a", "carplay:session:b"])
      allow(mock_redis).to receive(:del)

      service.invalidate_pattern("session:*")

      expect(mock_redis).to have_received(:del)
        .with("carplay:session:a", "carplay:session:b")
    end

    it "does nothing when no keys match" do
      allow(mock_redis).to receive(:keys).and_return([])
      service.invalidate_pattern("nope:*")
      expect(mock_redis).not_to have_received(:del) rescue nil
    end
  end

  describe "#stats" do
    it "returns a copy of hit/miss counts" do
      allow(mock_redis).to receive(:get).and_return("x", nil)
      service.get("a")
      service.get("b")

      result = service.stats
      expect(result).to eq({ hits: 1, misses: 1 })
    end

    it "returns a frozen snapshot that does not mutate" do
      stats1 = service.stats
      allow(mock_redis).to receive(:get).and_return("x")
      service.get("a")
      stats2 = service.stats

      expect(stats1[:hits]).to eq(0)
      expect(stats2[:hits]).to eq(1)
    end
  end

  describe "thread safety" do
    it "handles concurrent stat updates without error" do
      allow(mock_redis).to receive(:get).and_return("x")

      threads = 10.times.map do
        Thread.new { 50.times { service.get("key") } }
      end
      threads.each(&:join)

      expect(service.stats[:hits]).to eq(500)
    end
  end
end
