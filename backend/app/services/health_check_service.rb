# frozen_string_literal: true

class HealthCheckService
  HEALTHY = "healthy"
  DEGRADED = "degraded"
  UNHEALTHY = "unhealthy"

  def check_all
    results = {}

    results[:postgres] = check_postgres
    results[:redis] = check_redis
    results[:claude_api] = check_claude_api

    results
  end

  def overall_status(service_results)
    statuses = service_results.values.map { |r| r[:status] }

    if statuses.all? { |s| s == HEALTHY }
      HEALTHY
    elsif statuses.any? { |s| s == UNHEALTHY }
      UNHEALTHY
    else
      DEGRADED
    end
  end

  def record_snapshot!(service_results)
    service_results.each do |service_name, result|
      SystemHealthSnapshot.create!(
        service_name: service_name.to_s,
        status: result[:status],
        response_time_ms: result[:latency_ms],
        error_count: result[:status] == HEALTHY ? 0 : 1,
        metadata: result.except(:status, :latency_ms),
        recorded_at: Time.current
      )
    end
  end

  private

  def check_postgres
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ActiveRecord::Base.connection.active?
    latency = elapsed_ms(start)

    { status: HEALTHY, latency_ms: latency }
  rescue StandardError => e
    latency = elapsed_ms(start)
    { status: UNHEALTHY, latency_ms: latency, error: e.message }
  end

  def check_redis
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = REDIS.ping
    latency = elapsed_ms(start)

    if result == "PONG"
      { status: HEALTHY, latency_ms: latency }
    else
      { status: DEGRADED, latency_ms: latency, error: "Unexpected response: #{result}" }
    end
  rescue StandardError => e
    latency = elapsed_ms(start)
    { status: UNHEALTHY, latency_ms: latency, error: e.message }
  end

  def check_claude_api
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)

    unless api_key
      return { status: DEGRADED, latency_ms: 0, error: "API key not configured" }
    end

    connection = Faraday.new(url: "https://api.anthropic.com") do |f|
      f.options.timeout = 5
      f.options.open_timeout = 3
      f.headers["x-api-key"] = api_key
      f.headers["anthropic-version"] = "2023-06-01"
      f.headers["Content-Type"] = "application/json"
      f.adapter Faraday.default_adapter
    end

    response = connection.post("/v1/messages") do |req|
      req.body = JSON.generate({
        model: "claude-sonnet-4-20250514",
        max_tokens: 1,
        messages: [{ role: "user", content: "ping" }]
      })
    end

    latency = elapsed_ms(start)

    if response.status == 200
      { status: HEALTHY, latency_ms: latency }
    elsif response.status == 401
      { status: UNHEALTHY, latency_ms: latency, error: "Invalid API key" }
    elsif response.status == 429
      { status: DEGRADED, latency_ms: latency, error: "Rate limited" }
    else
      { status: DEGRADED, latency_ms: latency, error: "HTTP #{response.status}" }
    end
  rescue Faraday::TimeoutError
    latency = elapsed_ms(start)
    { status: UNHEALTHY, latency_ms: latency, error: "Connection timed out" }
  rescue Faraday::ConnectionFailed => e
    latency = elapsed_ms(start)
    { status: UNHEALTHY, latency_ms: latency, error: "Connection failed: #{e.message}" }
  rescue StandardError => e
    latency = elapsed_ms(start)
    { status: UNHEALTHY, latency_ms: latency, error: e.message }
  end

  def elapsed_ms(start)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
  end
end
