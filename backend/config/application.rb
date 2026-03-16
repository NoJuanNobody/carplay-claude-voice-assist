require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true
    config.active_job.queue_adapter = :sidekiq

    config.generators do |g|
      g.test_framework :rspec
    end

    # Load lib directory for metrics
    config.autoload_paths << Rails.root.join("lib")
    config.eager_load_paths << Rails.root.join("lib")

    # Metrics request instrumentation middleware
    config.middleware.use "Metrics::RequestMiddleware"
  end
end
