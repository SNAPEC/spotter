class ClarificationMailer < ApplicationMailer
  self.delivery_job = ClarificationMailDeliveryJob

  # The digest names neither a report nor what is waiting, in the same words for everyone: it may sit
  # in a mailbox for years. An account deactivated since the digest ran gets nothing.
  def digest(user)
    return unless user.reload.active?

    @url = login_url
    mail to: user.email
  end
end
