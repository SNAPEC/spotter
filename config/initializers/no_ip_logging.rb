# The logs must never carry the client IP address, a magic link token, nor any id: a report id logged
# with the time of a request could be matched against a sign-in mail in the provider's log.
Rails.application.config.log_tags = [ :request_id ]

module NoIpLogging
  UUID = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/i
  LOGIN_TOKEN = %r{(/login/)[^\s/?#"'<>]+}
  # Logstop scrubs the whole formatted line: the leading tags (request id, job id) are left out of it,
  # so a request or a job can still be followed.
  TAGS = /\A(?:\[[^\]\n]*\] )*/

  SCRUBBER = lambda do |line|
    tags = line[TAGS]
    tags + line.delete_prefix(tags).gsub(UUID, Logstop::FILTERED_STR).gsub(LOGIN_TOKEN, "\\1#{Logstop::FILTERED_STR}")
  end

  # Logstop's default rules (emails, phone numbers, URL passwords...) are kept, IPv4 addresses added.
  def self.install(logger)
    Logstop.guard(logger, ip: true, scrubber: SCRUBBER)
    logger
  end

  # Rails logs the client IP on the request line, IPv6 included, which Logstop does not catch.
  module RequestLine
    private

    # Overrides a private Rails 8.1 method: re-check it when upgrading Rails.
    def started_request_message(request)
      format('Started %s "%s" at %s', request.raw_request_method, request.filtered_path, Time.now)
    end
  end
end

# Every framework logs through Rails.logger: Action Pack, Active Job, Solid Queue.
Rails.logger.broadcasts.each { |logger| NoIpLogging.install(logger) }
Rails::Rack::Logger.prepend(NoIpLogging::RequestLine)

# A blob key gives access to the file in the bucket: Active Storage logs nothing.
require "active_storage/log_subscriber"
ActiveStorage::LogSubscriber.detach_from(:active_storage)
