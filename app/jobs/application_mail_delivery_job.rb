# The default delivery job logs its arguments, the user's GlobalID among them: kept out of the log so
# that no line ties an account to a mail, whatever the mail is about.
class ApplicationMailDeliveryJob < ActionMailer::MailDeliveryJob
  self.log_arguments = false

  queue_as :default
  # Any error, after the last attempt, ends here instead of in a failed execution, which would keep the
  # user's GlobalID. A failing hook is swallowed for the same reason.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, _error|
    job.delivery_abandoned
  rescue StandardError
    nil
  end
  discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound

  def delivery_abandoned
  end
end
