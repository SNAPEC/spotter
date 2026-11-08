# The default delivery job logs its arguments, the report's GlobalID among them, next to a timestamp:
# with the mail provider's own log, that would map a report to its author's address.
class ClarificationMailDeliveryJob < ActionMailer::MailDeliveryJob
  self.log_arguments = false

  queue_as :default
  discard_on ActiveJob::DeserializationError
end
