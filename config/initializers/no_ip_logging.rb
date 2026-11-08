# The request line must never carry the client IP address, a magic link token, nor any id: a report id
# logged with the time of the request could be matched against a sign-in mail in the provider's log.
Rails.application.config.log_tags = [ :request_id ]

module NoIpLogging
  UUID = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/i
  FILTERED = "[FILTERED]"

  private

  # Overrides a private Rails 8.1 method: re-check it when upgrading Rails.
  def started_request_message(request)
    path = request.filtered_path.sub(%r{\A/login/[^/?]+}, "/login/#{FILTERED}").gsub(UUID, FILTERED)
    format('Started %s "%s" at %s', request.raw_request_method, path, Time.now)
  end
end

Rails::Rack::Logger.prepend(NoIpLogging)

# The "Redirected to" line: a location holding an id is logged as [FILTERED] as a whole.
Rails.application.config.filter_redirect << NoIpLogging::UUID

# A 404 would log its exception message, "No route matches" or "Couldn't find Report", path or id included.
# The "Completed 404" line stays.
Rails.application.config.action_dispatch.log_rescued_responses = false
