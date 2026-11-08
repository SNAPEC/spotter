# The default delivery job logs its arguments, the user's GlobalID among them: kept out of the log so
# that no line ties an account to a mail, whatever the mail is about.
class ClarificationMailDeliveryJob < ActionMailer::MailDeliveryJob
  self.log_arguments = false

  queue_as :default
  discard_on ActiveJob::DeserializationError
  # After the last attempt the user's reports wait for the next digest. Handled here, the error leaves no
  # failed execution behind, which would keep the user's GlobalID.
  retry_on "ClarificationMailer::DeliveryFailed", wait: :polynomially_longer, attempts: 3 do |job, _error|
    Report.reopen_declarant_notices(job.arguments.last[:args].first)
  end
end
