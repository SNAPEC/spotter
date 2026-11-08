# The logs must never carry the client IP address, a magic link token, nor any id: a report id logged
# with the time of a request could be matched against a sign-in mail in the provider's log.
Rails.application.config.log_tags = [ :request_id ]

module NoIpLogging
  # Job ids are random and point to no record: kept so a job can be followed from enqueue to perform.
  UUID = /(?<!Job ID: |active_job_id: ")\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/i
  FILTERED = "[FILTERED]"

  # Masks every message before the tags are added, so the request id tag stays.
  module Formatter
    def call(severity, time, progname, msg)
      super(severity, time, progname, msg.is_a?(String) ? msg.gsub(UUID, FILTERED) : msg)
    end
  end

  def self.install(logger)
    logger.formatter ||= ActiveSupport::Logger::SimpleFormatter.new
    logger.formatter.extend(Formatter)
    logger
  end

  module RequestLine
    private

    # Overrides a private Rails 8.1 method: re-check it when upgrading Rails.
    def started_request_message(request)
      path = request.filtered_path.sub(%r{\A/login/[^/?]+}, "/login/#{FILTERED}")
      format('Started %s "%s" at %s', request.raw_request_method, path, Time.now)
    end
  end
end

# Every framework logs through Rails.logger: Action Pack, Active Job, Solid Queue.
Rails.logger.broadcasts.each { |logger| NoIpLogging.install(logger) }
Rails::Rack::Logger.prepend(NoIpLogging::RequestLine)
