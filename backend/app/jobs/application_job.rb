class ApplicationJob < ActiveJob::Base
  retry_on ActiveJob::DeserializationError
end
