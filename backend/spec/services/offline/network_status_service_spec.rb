require "spec_helper"
require "net/http"
require_relative "../../../app/services/offline/network_status_service"

RSpec.describe Offline::NetworkStatusService do
  subject(:service) { described_class.new }

  # Stub Rails.logger for unit tests outside Rails
  before do
    unless defined?(Rails)
      stub_const("Rails", double("Rails", logger: double("Logger", warn: nil, error: nil)))
    end
  end

  describe "#check_all" do
    it "returns a hash with all service statuses" do
      allow(service).to receive(:check_service).and_return(:healthy)

      result = service.check_all
      expect(result).to have_key(:claude_api)
      expect(result).to have_key(:redis)
      expect(result).to have_key(:postgres)
    end

    it "calls check_service for each service" do
      allow(service).to receive(:check_service).and_return(:healthy)

      service.check_all

      Offline::NetworkStatusService::SERVICES.each do |svc|
        expect(service).to have_received(:check_service).with(svc)
      end
    end

    it "returns individual statuses for each service" do
      allow(service).to receive(:check_service).with(:claude_api).and_return(:healthy)
      allow(service).to receive(:check_service).with(:redis).and_return(:unhealthy)
      allow(service).to receive(:check_service).with(:postgres).and_return(:healthy)

      result = service.check_all
      expect(result[:claude_api]).to eq(:healthy)
      expect(result[:redis]).to eq(:unhealthy)
      expect(result[:postgres]).to eq(:healthy)
    end
  end

  describe "#healthy?" do
    it "returns true when all services are healthy" do
      allow(service).to receive(:check_service).and_return(:healthy)
      expect(service.healthy?).to be true
    end

    it "returns false when any service is unhealthy" do
      allow(service).to receive(:check_service).with(:claude_api).and_return(:healthy)
      allow(service).to receive(:check_service).with(:redis).and_return(:unhealthy)
      allow(service).to receive(:check_service).with(:postgres).and_return(:healthy)

      expect(service.healthy?).to be false
    end

    it "returns false when all services are unhealthy" do
      allow(service).to receive(:check_service).and_return(:unhealthy)
      expect(service.healthy?).to be false
    end
  end

  describe "#degraded_services" do
    it "returns an empty array when all services are healthy" do
      allow(service).to receive(:check_service).and_return(:healthy)
      expect(service.degraded_services).to be_empty
    end

    it "returns only unhealthy services" do
      allow(service).to receive(:check_service).with(:claude_api).and_return(:unhealthy)
      allow(service).to receive(:check_service).with(:redis).and_return(:healthy)
      allow(service).to receive(:check_service).with(:postgres).and_return(:unhealthy)

      result = service.degraded_services
      expect(result).to contain_exactly(:claude_api, :postgres)
    end

    it "returns all services when none are healthy" do
      allow(service).to receive(:check_service).and_return(:unhealthy)
      expect(service.degraded_services).to contain_exactly(:claude_api, :redis, :postgres)
    end
  end

  describe "#check_service" do
    context "with Claude API" do
      it "returns :healthy on successful HTTP response" do
        http_double = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http_double)
        allow(http_double).to receive(:use_ssl=)
        allow(http_double).to receive(:open_timeout=)
        allow(http_double).to receive(:read_timeout=)
        allow(http_double).to receive(:request).and_return(Net::HTTPSuccess.allocate)
        allow(ENV).to receive(:fetch).with("CLAUDE_API_BASE_URL", anything).and_return("https://api.anthropic.com")
        allow(ENV).to receive(:fetch).with("CLAUDE_API_KEY", anything).and_return("test-key")

        expect(service.check_service(:claude_api)).to eq(:healthy)
      end

      it "returns :unhealthy on network error" do
        allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

        expect(service.check_service(:claude_api)).to eq(:unhealthy)
      end

      it "returns :unhealthy on timeout" do
        allow(Net::HTTP).to receive(:new).and_raise(Net::OpenTimeout)

        expect(service.check_service(:claude_api)).to eq(:unhealthy)
      end
    end

    context "with Redis" do
      it "returns :healthy when Redis responds with PONG" do
        redis_double = double("Redis", ping: "PONG")
        stub_const("REDIS", redis_double)

        expect(service.check_service(:redis)).to eq(:healthy)
      end

      it "returns :unhealthy when Redis is unreachable" do
        redis_double = double("Redis")
        allow(redis_double).to receive(:ping).and_raise(StandardError, "Connection refused")
        stub_const("REDIS", redis_double)

        expect(service.check_service(:redis)).to eq(:unhealthy)
      end

      it "returns :unhealthy when Redis returns unexpected response" do
        redis_double = double("Redis", ping: "ERROR")
        stub_const("REDIS", redis_double)

        expect(service.check_service(:redis)).to eq(:unhealthy)
      end
    end

    context "with PostgreSQL" do
      it "returns :healthy when database responds" do
        connection_double = double("Connection")
        allow(connection_double).to receive(:execute).with("SELECT 1").and_return(true)

        active_record_double = double("ActiveRecord::Base", connection: connection_double)
        stub_const("ActiveRecord::Base", active_record_double)

        expect(service.check_service(:postgres)).to eq(:healthy)
      end

      it "returns :unhealthy when database is unreachable" do
        active_record_double = double("ActiveRecord::Base")
        allow(active_record_double).to receive(:connection).and_raise(StandardError, "Connection refused")
        stub_const("ActiveRecord::Base", active_record_double)

        expect(service.check_service(:postgres)).to eq(:unhealthy)
      end
    end

    context "with unknown service" do
      it "returns :unhealthy" do
        expect(service.check_service(:unknown_service)).to eq(:unhealthy)
      end
    end
  end

  describe "SERVICES constant" do
    it "includes the three expected services" do
      expect(Offline::NetworkStatusService::SERVICES).to contain_exactly(:claude_api, :redis, :postgres)
    end
  end

  describe "HEALTH_CHECK_TIMEOUT constant" do
    it "is a positive integer" do
      expect(Offline::NetworkStatusService::HEALTH_CHECK_TIMEOUT).to be > 0
    end
  end
end
