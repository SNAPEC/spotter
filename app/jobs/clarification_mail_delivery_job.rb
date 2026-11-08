class ClarificationMailDeliveryJob < ApplicationMailDeliveryJob
  # The user's reports wait for the next digest.
  def delivery_abandoned
    Report.reopen_declarant_notices(arguments.last[:args].first)
  end
end
