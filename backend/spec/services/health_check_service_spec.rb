# frozen_string_literal: true

require "rails_helper"

RSpec.describe HealthCheckService do
  subject(:service) { described_class.new }

  describe "#check_all" do
    it "returns results for all three services" do
      allow(ActiveRecord::Base.connection).to receive(:active?).and_return(true)
      allow(REDIS).to receive(:ping).and_return("PONG")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return(nil)

      results = service.check_all

      expect(results).to have_key(:postgres)
      expect(results).to have_key(:redis)
      expect(results).to have_key(:claude_api)
    end
  end

  describe "postgres check" do
    it "returns healthy when connection is active" do
      allow(ActiveRecord::Base.connection).to receive(:active?).and_return(true)
      allow(REDIS).to receive(:ping).and_return("PONG")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return(nil)

      results = service.check_all

      expect(results[:postgres][:status]).to eq("healthy")
      expect(results[:postgres][:latency_ms]).to be_a(Integer)
    end

    it "returns unhealthy when connection fails" do
      allow(ActiveRecord::Base.connection).to receive(:active?).and_raise(PG::ConnectionBad.new("connection refused"))
      allow(REDIS).to receive(:ping).and_return("PONG")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return(nil)

      results = service.check_all

      expect(results[:postgres][:status]).to eq("unhealthy")
      expect(results[:postgres][:error]).to be_present
    end
  end

  describe "redis check" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:active?).and_return(true)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return(nil)
    end

    it "returns healthy when redis responds with PONG" do
      allow(REDIS).to receive(:ping).and_return("PONG")

      results = service.check_all

      expect(results[:redis][:status]).to eq("healthy")
      expect(results[:redis][:latency_ms]).to be_a(Integer)
    end

    it "returns unhealthy when redis raises an error" do
      allow(REDIS).to receive(:ping).and_raise(Redis::CannotConnectError.new("Connection refused"))

      results = service.check_all

      expect(results[:redis][:status]).to eq("unhealthy")
      expect(results[:redis][:error]).to include("Connection refused")
    end

    it "returns degraded when redis returns unexpected response" do
      allow(REDIS).to receive(:ping).and_return("LOADING")

      results = service.check_all

      expect(results[:redis][:status]).to eq("degraded")
    end
  end

  describe "claude_api check" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:active?).and_return(true)
      allow(REDIS).to receive(:ping).and_return("PONG")
    end

    it "returns degraded when API key is not configured" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return(nil)

      results = service.check_all

      expect(results[:claude_api][:status]).to eq("degraded")
      expect(results[:claude_api][:error]).to include("not configured")
    end

    it "returns healthy when API responds with 200" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return("test-key")

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/v1/messages") { [200, { "Content-Type" => "application/json" }, "{}"] }
      end

      allow(Faraday).to receive(:new).and_wrap_original do |method, *args, &block|
        method.call(*args) do |f|
          block&.call(f)
          f.adapter :test, stubs
        end
      end

      results = service.check_all

      expect(results[:claude_api][:status]).to eq("healthy")
    end

    it "returns unhealthy when API responds with 401" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return("bad-key")

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/v1/messages") { [401, {}, '{"error":{"message":"Invalid API key"}}'] }
      end

      allow(Faraday).to receive(:new).and_wrap_original do |method, *args, &block|
        method.call(*args) do |f|
          block&.call(f)
          f.adapter :test, stubs
        end
      end

      results = service.check_all

      expect(results[:claude_api][:status]).to eq("unhealthy")
      expect(results[:claude_api][:error]).to include("Invalid API key")
    end

    it "returns degraded when API responds with 429" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return("test-key")

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/v1/messages") { [429, {}, '{"error":{"message":"Rate limited"}}'] }
      end

      allow(Faraday).to receive(:new).and_wrap_original do |method, *args, &block|
        method.call(*args) do |f|
          block&.call(f)
          f.adapter :test, stubs
        end
      end

      results = service.check_all

      expect(results[:claude_api][:status]).to eq("degraded")
    end

    it "returns unhealthy on connection timeout" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return("test-key")

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/v1/messages") { raise Faraday::TimeoutError, "timeout" }
      end

      allow(Faraday).to receive(:new).and_wrap_original do |method, *args, &block|
        method.call(*args) do |f|
          block&.call(f)
          f.adapter :test, stubs
        end
      end

      results = service.check_all

      expect(results[:claude_api][:status]).to eq("unhealthy")
      expect(results[:claude_api][:error]).to include("timed out")
    end
  end

  describe "#overall_status" do
    it "returns healthy when all services are healthy" do
      results = {
        postgres: { status: "healthy" },
        redis: { status: "healthy" },
        claude_api: { status: "healthy" }
      }

      expect(service.overall_status(results)).to eq("healthy")
    end

    it "returns unhealthy when any service is unhealthy" do
      results = {
        postgres: { status: "healthy" },
        redis: { status: "unhealthy" },
        claude_api: { status: "healthy" }
      }

      expect(service.overall_status(results)).to eq("unhealthy")
    end

    it "returns degraded when a service is degraded but none unhealthy" do
      results = {
        postgres: { status: "healthy" },
        redis: { status: "healthy" },
        claude_api: { status: "degraded" }
      }

      expect(service.overall_status(results)).to eq("degraded")
    end
  end

  describe "#record_snapshot!" do
    it "creates SystemHealthSnapshot records for each service" do
      results = {
        postgres: { status: "healthy", latency_ms: 3 },
        redis: { status: "healthy", latency_ms: 1 },
        claude_api: { status: "degraded", latency_ms: 200, error: "Rate limited" }
      }

      expect {
        service.record_snapshot!(results)
      }.to change(SystemHealthSnapshot, :count).by(3)

      snapshot = SystemHealthSnapshot.find_by(service_name: "claude_api")
      expect(snapshot.status).to eq("degraded")
      expect(snapshot.response_time_ms).to eq(200)
    end
  end
end
