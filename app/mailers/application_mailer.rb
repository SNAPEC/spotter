class ApplicationMailer < ActionMailer::Base
  class DeliveryFailed < StandardError; end

  default from: "from@example.com"
  layout "mailer"
  self.delivery_job = ApplicationMailDeliveryJob

  # A delivery error usually quotes the recipient: re-raised as is, it would land in the job log and in
  # Sentry next to the user's GlobalID. It is replaced by a bare error, without its cause.
  rescue_from "Net::SMTPError", "OpenSSL::SSL::SSLError", IOError, SocketError, SystemCallError, Timeout::Error do
    raise DeliveryFailed, cause: nil
  end
end
