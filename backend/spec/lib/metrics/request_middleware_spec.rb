# frozen_string_literal: true

require "rails_helper"
require "metrics/collector"
require "metrics/request_middleware"

RSpec.describe Metrics::RequestMiddleware do
  let(:app) { ->(env) { [200, { "Content-Type" => "application/json" }, ["OK"]] } }
  let(:middleware) { described_class.new(app) }
  let(:collector) { Metrics::Collector.instance }

  before { collector.reset! }

  def env_for(path, method: "GET")
    {
      "PATH_INFO" => path,
      "REQUEST_METHOD" => method
    }
  end

  it "records request metrics" do
    middleware.call(env_for("/api/v1/sessions"))

    snapshot = collector.snapshot
    expect(snapshot[:requests_total]).to eq(1)
  end

  it "passes through the response unchanged" do
    status, headers, body = middleware.call(env_for("/api/v1/sessions"))

    expect(status).to eq(200)
    expect(body).to eq(["OK"])
  end

  it "skips health check endpoints" do
    middleware.call(env_for("/api/v1/health"))
    middleware.call(env_for("/api/v1/health/detailed"))
    middleware.call(env_for("/up"))

    snapshot = collector.snapshot
    expect(snapshot[:requests_total]).to eq(0)
  end

  it "records metrics for non-health paths" do
    middleware.call(env_for("/api/v1/sessions", method: "POST"))
    middleware.call(env_for("/api/v1/vehicles"))

    snapshot = collector.snapshot
    expect(snapshot[:requests_total]).to eq(2)
  end

  context "when the app raises an error" do
    let(:failing_app) { ->(_env) { raise StandardError, "boom" } }
    let(:middleware) { described_class.new(failing_app) }

    it "records the error and re-raises" do
      expect {
        middleware.call(env_for("/api/v1/sessions"))
      }.to raise_error(StandardError, "boom")

      snapshot = collector.snapshot
      expect(snapshot[:requests_total]).to eq(1)
      expect(snapshot[:errors_total]).to be >= 1
    end
  end
end
