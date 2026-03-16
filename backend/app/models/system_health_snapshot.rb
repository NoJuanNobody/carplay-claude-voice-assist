class SystemHealthSnapshot < ApplicationRecord
  enum :status, { healthy: "healthy", degraded: "degraded", unhealthy: "unhealthy" }

  validates :service_name, presence: true
  validates :status, presence: true
  validates :recorded_at, presence: true
end
