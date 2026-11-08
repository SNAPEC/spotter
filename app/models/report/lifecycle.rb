module Report::Lifecycle
  extend ActiveSupport::Concern

  OWNERSHIP_DAYS = 60

  included do
    Report::STATUSES.each do |status|
      define_method(:"#{status}?") { self.status == status }
    end
  end

  # Only the content of the form: state, dates and digests stay in the lifecycle's hands.
  def save_draft!(attrs)
    attrs = attrs.to_h.stringify_keys
    unexpected = attrs.keys - Report::DRAFT_ATTRIBUTES
    raise ArgumentError, "not draft content: #{unexpected.join(", ")}" if unexpected.any?

    with_lock do
      raise Report::InvalidTransition, "not an open draft" unless open_draft?

      assign_attributes(attrs)
      self.draft_expires_on = Date.current + Report::DRAFT_VALIDITY
      save!
      report_ownership&.update!(cutoff_on: draft_cutoff_on)
    end
  end

  # Returns the tracking code in clear in anonymous mode, the only time it exists outside the
  # declarant's hands; nil in confidential mode.
  def submit!
    with_lock do
      raise Report::InvalidTransition, "cannot submit from #{status}" unless open_draft?
      raise Report::InvalidTransition, "authorship link already cut" if confidential? && report_ownership.nil?

      code = RecoveryCode.generate_one if anonymous?
      update!(
        status: "submitted",
        submitted_on: Date.current.beginning_of_month,
        draft_expires_on: nil,
        draft_token_digest: nil,
        tracking_code_digest: code && Report.digest(RecoveryCode.normalize(code), purpose: :tracking_code)
      )
      report_ownership&.update!(cutoff_on: Date.current + OWNERSHIP_DAYS)
      code
    end
  end

  def start_analysis!
    transition!(from: "submitted", to: "analyzing")
  end

  def ready_for_validation!
    transition!(from: "analyzing", to: "in_validation")
  end

  def validate!(analyst)
    decide!(analyst, from: %w[in_validation], to: "validated")
  end

  def reject!(analyst)
    decide!(analyst, from: %w[submitted analyzing in_validation], to: "rejected")
  end

  private
    def decide!(analyst, from:, to:)
      raise Report::NotAllowed, "only staff decide on a report" unless analyst&.staff?

      transition!(from: from, to: to) { purge_after_decision! }
    end

    # The row lock makes the check and the change atomic, and the purge shares the transaction.
    def transition!(from:, to:)
      with_lock do
        raise Report::InvalidTransition, "cannot go from #{status} to #{to}" unless Array(from).include?(status)

        update!(status: to)
        yield if block_given?
      end
    end

    # Everything that could point back to the author or quote them goes, in one transaction.
    def purge_after_decision!
      narrative&.purge_raw!
      report_ownership&.destroy!
      update!(tracking_code_digest: nil, draft_token_digest: nil)
    end
end
