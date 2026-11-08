# The logs must never carry the client IP address, a magic link token, nor any id: a report id logged
# with the time of a request could be matched against a sign-in mail in the provider's log.
Rails.application.config.log_tags = [ :request_id ]

module NoIpLogging
  UUID = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/i
  FILTERED = "[FILTERED]"

  def self.mask(text)
    text.is_a?(String) ? text.gsub(UUID, FILTERED) : text
  end

  module RequestLine
    private

    # Overrides a private Rails 8.1 method: re-check it when upgrading Rails.
    def started_request_message(request)
      path = request.filtered_path.sub(%r{\A/login/[^/?]+}, "/login/#{FILTERED}")
      format('Started %s "%s" at %s', request.raw_request_method, NoIpLogging.mask(path), Time.now)
    end
  end

  # An unrescued exception logs its message, which may quote a record id.
  module ExceptionMessage
    private

    # Overrides a private Rails 8.1 method: re-check it when upgrading Rails.
    def compose_exception_message(wrapper)
      super.map { |line| NoIpLogging.mask(line) }
    end
  end

  # Every line of a log subscriber, an error message included. Log tags, such as the job id, are kept.
  module SubscriberLines
    %w[debug info warn error fatal unknown].each do |level|
      define_method(level) do |progname = nil, &block|
        if block
          super(progname) { NoIpLogging.mask(block.call) }
        else
          super(NoIpLogging.mask(progname))
        end
      end
    end
  end
end

Rails::Rack::Logger.prepend(NoIpLogging::RequestLine)
ActionDispatch::DebugExceptions.prepend(NoIpLogging::ExceptionMessage)
ActiveSupport.on_load(:active_job) { ActiveJob::LogSubscriber.prepend(NoIpLogging::SubscriberLines) }
ActiveSupport.on_load(:solid_queue) { SolidQueue::LogSubscriber.prepend(NoIpLogging::SubscriberLines) }

# The "Redirected to" line: a location holding an id is logged as [FILTERED] as a whole.
Rails.application.config.filter_redirect << NoIpLogging::UUID

# A 404 would log its exception message, "No route matches" or "Couldn't find Report", path or id included.
# The "Completed 404" line stays.
Rails.application.config.action_dispatch.log_rescued_responses = false
