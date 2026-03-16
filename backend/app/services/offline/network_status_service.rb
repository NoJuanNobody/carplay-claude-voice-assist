# frozen_string_literal: true

module Offline
  class NetworkStatusService
    SERVICES = %i[claude_api redis postgres].freeze

    HEALTH_CHECK_TIMEOUT = 5 # seconds

    # Checks connectivity to all external services.
    #
    # @return [Hash] e.g. { claude_api: :healthy, redis: :healthy, postgres: :healthy }
    def check_all
      results = {}
      SERVICES.each do |service|
        results[service] = check_service(service)
      end
      results
    end

    # Returns true if all services are healthy.
    #
    # @return [Boolean]
    def healthy?
      check_all.values.all? { |status| status == :healthy }
    end

    # Returns a list of services that are not healthy.
    #
    # @return [Array<Symbol>]
    def degraded_services
      check_all.select { |_, status| status != :healthy }.keys
    end

    # Checks a single service's health.
    #
    # @param service [Symbol] one of :claude_api, :redis, :postgres
    # @return [Symbol] :healthy or :unhealthy
    def check_service(service)
      case service
      when :claude_api
        check_claude_api
      when :redis
        check_redis
      when :postgres
        check_postgres
      else
        :unhealthy
      end
    end

    private

    def check_claude_api
      uri = URI.parse(claude_api_health_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = HEALTH_CHECK_TIMEOUT
      http.read_timeout = HEALTH_CHECK_TIMEOUT

      request = Net::HTTP::Get.new(uri.request_uri)
      request["Authorization"] = "Bearer #{claude_api_key}"
      request["Content-Type"] = "application/json"

      response = http.request(request)
      response.is_a?(Net::HTTPSuccess) ? :healthy : :unhealthy
    rescue StandardError => e
      Rails.logger.warn("Claude API health check failed: #{e.message}")
      :unhealthy
    end

    def check_redis
      redis = REDIS
      redis.ping == "PONG" ? :healthy : :unhealthy
    rescue StandardError => e
      Rails.logger.warn("Redis health check failed: #{e.message}")
      :unhealthy
    end

    def check_postgres
      ActiveRecord::Base.connection.execute("SELECT 1")
      :healthy
    rescue StandardError => e
      Rails.logger.warn("PostgreSQL health check failed: #{e.message}")
      :unhealthy
    end

    def claude_api_health_url
      base = ENV.fetch("CLAUDE_API_BASE_URL", "https://api.anthropic.com")
      "#{base}/v1/messages"
    end

    def claude_api_key
      ENV.fetch("CLAUDE_API_KEY", "")
    end
  end
end
