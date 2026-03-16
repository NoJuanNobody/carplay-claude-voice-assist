# frozen_string_literal: true

module Safety
  class SafetyMiddleware
    CONVERSATION_PATH_PATTERN = %r{/api/v1/sessions/[^/]+/messages}

    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)

      # Inject driving state into the request environment for downstream use
      inject_driving_state(env, request)

      status, headers, response = @app.call(env)

      # Only validate conversation message responses
      if conversation_response?(request, status)
        status, headers, response = validate_response(env, status, headers, response)
      end

      [status, headers, response]
    end

    private

    def inject_driving_state(env, request)
      driving_state = extract_driving_state(request)
      env["safety.driving_state"] = driving_state
    end

    def extract_driving_state(request)
      # Try header first (set by iOS client)
      header_state = request.get_header("HTTP_X_DRIVING_STATE")
      return header_state.to_sym if header_state.present? && valid_state?(header_state)

      # Try query param
      param_state = request.params["driving_state"]
      return param_state.to_sym if param_state.present? && valid_state?(param_state)

      # Default to city (safer default)
      :city
    end

    def valid_state?(state)
      %w[parked city highway emergency].include?(state.to_s)
    end

    def conversation_response?(request, status)
      request.path.match?(CONVERSATION_PATH_PATTERN) &&
        request.post? &&
        status == 200
    end

    def validate_response(env, status, headers, response)
      driving_state = env["safety.driving_state"] || :city

      body = extract_body(response)
      return [status, headers, response] unless body

      begin
        json = JSON.parse(body)
        response_text = json.dig("message", "content") || json.dig("response", "text")
        return [status, headers, response] unless response_text

        validator = ResponseValidator.new
        result = validator.validate(response_text, driving_state: driving_state)

        unless result[:valid]
          # Replace the response text with the validated version
          if json.dig("message", "content")
            json["message"]["content"] = result[:modified_text]
          elsif json.dig("response", "text")
            json["response"]["text"] = result[:modified_text]
          end

          json["safety"] = {
            violations: result[:violations].map(&:to_s),
            driving_state: driving_state.to_s,
            was_modified: true
          }

          new_body = JSON.generate(json)
          headers["Content-Length"] = new_body.bytesize.to_s
          response = [new_body]
        end
      rescue JSON::ParserError
        # Not JSON, pass through
      end

      [status, headers, response]
    end

    def extract_body(response)
      parts = []
      response.each { |part| parts << part }
      parts.join
    end
  end
end
