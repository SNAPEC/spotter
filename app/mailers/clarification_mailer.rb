class ClarificationMailer < ApplicationMailer
  class DeliveryFailed < StandardError; end

  # A delivery error usually quotes the recipient: re-raised as is, it would land in the failed jobs table
  # and in Sentry next to the report's GlobalID. It is replaced by a bare error, without its cause.
  rescue_from "Net::SMTPError", "OpenSSL::SSL::SSLError", IOError, SocketError, SystemCallError, Timeout::Error do
    raise DeliveryFailed, cause: nil
  end

  # The address is looked up at send time through the ownership, never carried by the job. Without a
  # live link (anonymous report, link cut or due), nothing is sent. The mail carries one link and
  # nothing of the report, not even the question: it may sit in a mailbox for years.
  def requested(report)
    user = ReportOwnership.live.find_by(report_id: report.id)&.user
    return unless user

    @url = root_url
    mail to: user.email
  end
end
