# frozen_string_literal: true

class CacheService
  PREFIX = "carplay"

  TTL_POLICIES = {
    "session"     => 1800,  # 30 minutes
    "profile"     => 3600,  # 1 hour
    "vehicle"     => 300,   # 5 minutes
    "integration" => 900,   # 15 minutes
    "health"      => 60     # 1 minute
  }.freeze

  attr_reader :namespace

  def initialize(namespace: nil)
    @namespace = namespace
    @stats = { hits: 0, misses: 0 }
    @mutex = Mutex.new
  end

  # --- Core operations ---

  def get(key)
    value = redis.get(prefixed(key))

    @mutex.synchronize do
      if value.nil?
        @stats[:misses] += 1
      else
        @stats[:hits] += 1
      end
    end

    return nil if value.nil?

    deserialize(value)
  end

  def set(key, value, ttl: nil)
    ttl ||= ttl_for(key)
    serialized = serialize(value)

    if ttl
      redis.setex(prefixed(key), ttl, serialized)
    else
      redis.set(prefixed(key), serialized)
    end
  end

  def delete(key)
    redis.del(prefixed(key))
  end

  def exists?(key)
    redis.exists?(prefixed(key))
  end

  def expire(key, ttl)
    redis.expire(prefixed(key), ttl)
  end

  # --- Session convenience ---

  def get_session(session_id)
    get("session:#{session_id}")
  end

  def set_session(session_id, data)
    set("session:#{session_id}", data, ttl: TTL_POLICIES["session"])
  end

  # --- Profile convenience ---

  def get_profile(user_id)
    get("profile:#{user_id}")
  end

  def set_profile(user_id, data)
    set("profile:#{user_id}", data, ttl: TTL_POLICIES["profile"])
  end

  # --- Vehicle state convenience ---

  def get_vehicle_state(vehicle_id)
    get("vehicle:#{vehicle_id}")
  end

  def set_vehicle_state(vehicle_id, data)
    set("vehicle:#{vehicle_id}", data, ttl: TTL_POLICIES["vehicle"])
  end

  # --- Pattern invalidation ---

  def invalidate_pattern(pattern)
    keys = redis.keys(prefixed(pattern))
    redis.del(*keys) if keys.any?
  end

  # --- Stats ---

  def stats
    @mutex.synchronize { @stats.dup }
  end

  private

  def redis
    REDIS
  end

  def prefixed(key)
    parts = [PREFIX]
    parts << @namespace if @namespace
    parts << key
    parts.join(":")
  end

  def ttl_for(key)
    segment = key.to_s.split(":").first
    TTL_POLICIES[segment]
  end

  def serialize(value)
    case value
    when String
      value
    else
      JSON.generate(value)
    end
  end

  def deserialize(value)
    JSON.parse(value)
  rescue JSON::ParserError
    value
  end
end
