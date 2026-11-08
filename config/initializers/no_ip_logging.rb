# The request line must never carry the client IP address.
Rails.application.config.log_tags = [ :request_id ]

module NoIpLogging
  private

  # Overrides a private Rails 8.1 method: re-check it when upgrading Rails.
  def started_request_message(request)
    format('Started %s "%s" at %s', request.raw_request_method, request.filtered_path, Time.now)
  end
end

Rails::Rack::Logger.prepend(NoIpLogging)
