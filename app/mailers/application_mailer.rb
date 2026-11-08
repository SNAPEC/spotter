class ApplicationMailer < ActionMailer::Base
  class DeliveryFailed < StandardError; end

  default from: "from@example.com"
  layout "mailer"
  self.delivery_job = ApplicationMailDeliveryJob

  # A delivery error usually quotes the recipient: re-raised as is, it would reach the job log and
  # Sentry. It is replaced by an error that names only the original class, without its cause.
  rescue_from StandardError do |error|
    raise DeliveryFailed, error.class.name, cause: nil
  end

  # Ours, not the provider's: a vanished record is discarded by the job, a broken template must show.
  rescue_from ActiveRecord::RecordNotFound, ActionView::Template::Error do |error|
    raise error
  end
end
