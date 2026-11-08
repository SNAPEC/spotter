class ClarificationMailer < ApplicationMailer
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
