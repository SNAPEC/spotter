# The default delivery job logs its arguments, the user's GlobalID among them: kept out of the log so
# that no line ties an account to a mail, whatever the mail is about.
class ClarificationMailDeliveryJob < ActionMailer::MailDeliveryJob
  self.log_arguments = false

  queue_as :default
  discard_on ActiveJob::DeserializationError
end
