class ClarificationMailer < ApplicationMailer
  class DeliveryFailed < StandardError; end

  self.delivery_job = ClarificationMailDeliveryJob

  # A delivery error usually quotes the recipient: re-raised as is, it would land in the failed jobs table
  # and in Sentry next to the user's GlobalID. It is replaced by a bare error, without its cause.
  rescue_from "Net::SMTPError", "OpenSSL::SSL::SSLError", IOError, SocketError, SystemCallError, Timeout::Error do
    raise DeliveryFailed, cause: nil
  end

  # The digest names neither a report nor what is waiting, in the same words for everyone: it may sit
  # in a mailbox for years. An account deactivated since the digest ran gets nothing.
  def digest(user)
    return unless user.reload.active?

    @url = login_url
    mail to: user.email
  end
end
