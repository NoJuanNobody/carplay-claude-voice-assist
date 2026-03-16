# frozen_string_literal: true

require "rails_helper"

RSpec.describe Safety::SafetyMiddleware do
  let(:inner_app) { ->(env) { [status, response_headers, [body]] } }
  let(:middleware) { described_class.new(inner_app) }
  let(:status) { 200 }
  let(:response_headers) { { "Content-Type" => "application/json" } }
  let(:body) { '{"message":{"content":"Short reply."}}' }

  def build_env(path: "/api/v1/sessions/123/messages", method: "POST", headers: {})
    env = Rack::MockRequest.env_for(path, method: method)
    headers.each { |k, v| env["HTTP_#{k.upcase.tr('-', '_')}"] = v }
    env
  end

  describe "driving state injection" do
    it "injects driving state from X-Driving-State header" do
      env = build_env(headers: { "X-Driving-State" => "highway" })
      middleware.call(env)

      expect(env["safety.driving_state"]).to eq(:highway)
    end

    it "injects driving state from query param" do
      env = build_env(path: "/api/v1/sessions/123/messages?driving_state=parked")
      middleware.call(env)

      expect(env["safety.driving_state"]).to eq(:parked)
    end

    it "defaults to city when no state provided" do
      env = build_env
      middleware.call(env)

      expect(env["safety.driving_state"]).to eq(:city)
    end

    it "defaults to city for invalid state" do
      env = build_env(headers: { "X-Driving-State" => "invalid" })
      middleware.call(env)

      expect(env["safety.driving_state"]).to eq(:city)
    end
  end

  describe "response validation" do
    context "for conversation messages" do
      it "passes through short valid responses unchanged" do
        env = build_env
        _status, _headers, response = middleware.call(env)

        parsed = JSON.parse(response.first)
        expect(parsed["message"]["content"]).to eq("Short reply.")
        expect(parsed["safety"]).to be_nil
      end

      it "modifies responses that violate safety rules" do
        long_body = {
          message: {
            content: "First. Second. Third. Fourth. Fifth. Sixth."
          }
        }.to_json

        app = ->(_env) { [200, { "Content-Type" => "application/json" }, [long_body]] }
        mw = described_class.new(app)
        env = build_env(headers: { "X-Driving-State" => "highway" })

        _status, _headers, response = mw.call(env)
        parsed = JSON.parse(response.first)

        expect(parsed["safety"]).to be_present
        expect(parsed["safety"]["was_modified"]).to be true
        expect(parsed["safety"]["violations"]).to include("response_too_long")
        expect(parsed["message"]["content"]).to include("I'll tell you more when you're parked")
      end

      it "redacts phone numbers while driving" do
        phone_body = {
          message: { content: "Call 555-123-4567." }
        }.to_json

        app = ->(_env) { [200, { "Content-Type" => "application/json" }, [phone_body]] }
        mw = described_class.new(app)
        env = build_env(headers: { "X-Driving-State" => "city" })

        _status, _headers, response = mw.call(env)
        parsed = JSON.parse(response.first)

        expect(parsed["message"]["content"]).to include("[phone number hidden while driving]")
      end
    end

    context "for non-conversation paths" do
      it "does not validate responses" do
        env = build_env(path: "/api/v1/vehicles")
        _status, _headers, response = middleware.call(env)

        parsed = JSON.parse(response.first)
        expect(parsed["safety"]).to be_nil
      end
    end

    context "for non-POST requests" do
      it "does not validate GET responses" do
        env = build_env(method: "GET")
        _status, _headers, response = middleware.call(env)

        parsed = JSON.parse(response.first)
        expect(parsed["safety"]).to be_nil
      end
    end

    context "for non-200 responses" do
      let(:status) { 422 }

      it "does not validate error responses" do
        env = build_env
        _status, _headers, response = middleware.call(env)

        parsed = JSON.parse(response.first)
        expect(parsed["safety"]).to be_nil
      end
    end
  end
end
