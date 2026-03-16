# frozen_string_literal: true

require "rails_helper"
require "metrics/collector"

RSpec.describe Metrics::Collector do
  subject(:collector) { described_class.instance }

  before { collector.reset! }

  describe "#record_request" do
    it "increments the total request count" do
      collector.record_request("/api/v1/sessions", "POST", 200, 50)
      collector.record_request("/api/v1/sessions", "GET", 200, 30)

      snapshot = collector.snapshot
      expect(snapshot[:requests_total]).to eq(2)
    end

    it "tracks status code counts" do
      collector.record_request("/test", "GET", 200, 10)
      collector.record_request("/test", "GET", 200, 15)
      collector.record_request("/test", "POST", 422, 20)

      snapshot = collector.snapshot
      expect(snapshot[:status_counts][200]).to eq(2)
      expect(snapshot[:status_counts][422]).to eq(1)
    end

    it "counts errors for 4xx and 5xx status codes" do
      collector.record_request("/test", "GET", 200, 10)
      collector.record_request("/test", "GET", 404, 10)
      collector.record_request("/test", "POST", 500, 10)

      snapshot = collector.snapshot
      expect(snapshot[:errors_total]).to eq(2)
    end

    it "computes average response time" do
      collector.record_request("/test", "GET", 200, 40)
      collector.record_request("/test", "GET", 200, 60)

      snapshot = collector.snapshot
      expect(snapshot[:avg_response_ms]).to eq(50.0)
    end

    it "computes error rate as a percentage" do
      collector.record_request("/test", "GET", 200, 10)
      collector.record_request("/test", "GET", 200, 10)
      collector.record_request("/test", "GET", 200, 10)
      collector.record_request("/test", "GET", 500, 10)

      snapshot = collector.snapshot
      expect(snapshot[:error_rate]).to eq(25.0)
    end
  end

  describe "#record_error" do
    it "increments the error count" do
      collector.record_error("RuntimeError", "Something went wrong")

      snapshot = collector.snapshot
      expect(snapshot[:errors_total]).to eq(1)
    end

    it "stores recent errors with type, message, and timestamp" do
      collector.record_error("TimeoutError", "Request timed out")

      snapshot = collector.snapshot
      expect(snapshot[:recent_errors].size).to eq(1)
      expect(snapshot[:recent_errors].first[:type]).to eq("TimeoutError")
      expect(snapshot[:recent_errors].first[:message]).to eq("Request timed out")
      expect(snapshot[:recent_errors].first[:timestamp]).to be_present
    end

    it "caps recent errors at 100" do
      105.times { |i| collector.record_error("Error", "Error #{i}") }

      snapshot = collector.snapshot
      expect(snapshot[:recent_errors].size).to eq(100)
    end
  end

  describe "#record_session_event" do
    it "increments active sessions on start" do
      collector.record_session_event(:start)
      collector.record_session_event(:start)

      snapshot = collector.snapshot
      expect(snapshot[:active_sessions]).to eq(2)
    end

    it "decrements active sessions on end" do
      collector.record_session_event(:start)
      collector.record_session_event(:start)
      collector.record_session_event(:end)

      snapshot = collector.snapshot
      expect(snapshot[:active_sessions]).to eq(1)
    end

    it "does not go below zero" do
      collector.record_session_event(:end)

      snapshot = collector.snapshot
      expect(snapshot[:active_sessions]).to eq(0)
    end
  end

  describe "#snapshot" do
    it "returns a complete metrics hash" do
      snapshot = collector.snapshot

      expect(snapshot).to include(
        :requests_total,
        :errors_total,
        :avg_response_ms,
        :error_rate,
        :active_sessions,
        :status_counts,
        :recent_errors,
        :uptime_seconds
      )
    end

    it "returns zero values when empty" do
      snapshot = collector.snapshot

      expect(snapshot[:requests_total]).to eq(0)
      expect(snapshot[:errors_total]).to eq(0)
      expect(snapshot[:avg_response_ms]).to eq(0.0)
      expect(snapshot[:error_rate]).to eq(0.0)
      expect(snapshot[:active_sessions]).to eq(0)
    end
  end

  describe "#reset!" do
    it "clears all metrics" do
      collector.record_request("/test", "GET", 200, 50)
      collector.record_error("Error", "fail")
      collector.record_session_event(:start)

      collector.reset!

      snapshot = collector.snapshot
      expect(snapshot[:requests_total]).to eq(0)
      expect(snapshot[:errors_total]).to eq(0)
      expect(snapshot[:active_sessions]).to eq(0)
      expect(snapshot[:recent_errors]).to be_empty
    end
  end

  describe "thread safety" do
    it "handles concurrent writes without errors" do
      threads = 10.times.map do
        Thread.new do
          100.times do
            collector.record_request("/test", "GET", 200, rand(100))
          end
        end
      end

      threads.each(&:join)

      snapshot = collector.snapshot
      expect(snapshot[:requests_total]).to eq(1000)
    end
  end
end
