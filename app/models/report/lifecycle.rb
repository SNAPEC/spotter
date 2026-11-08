module Report::Lifecycle
  extend ActiveSupport::Concern

  OWNERSHIP_DAYS = 60
  DECIDED_STATUSES = %w[validated rejected].freeze

  included do
    Report::STATUSES.each do |status|
      define_method(:"#{status}?") { self.status == status }
    end

    scope :decided, -> { where(status: DECIDED_STATUSES) }
    validate :status_changes_through_lifecycle
  end

  # Only the content of the form: state, dates and digests stay in the lifecycle's hands.
  def save_draft!(attrs)
    attrs = attrs.to_h.deep_stringify_keys
    check_draft_keys!(attrs.keys, Report::DRAFT_ATTRIBUTES)
    check_draft_keys!(attrs.fetch("narrative_attributes", {}).keys, Report::DRAFT_NARRATIVE_ATTRIBUTES)
    casualties = attrs.fetch("casualties_attributes", [])
    (casualties.is_a?(Hash) ? casualties.values : casualties).each do |casualty|
      check_draft_keys!(casualty.keys, Report::DRAFT_CASUALTY_ATTRIBUTES)
    end

    with_lock do
      raise Report::InvalidTransition, "not an open draft" unless open_draft?

      assign_attributes(attrs)
      self.draft_expires_on = Date.current + Report::DRAFT_VALIDITY
      save!
      report_ownership&.update!(cutoff_on: draft_cutoff_on)
    end
  rescue ActiveRecord::RecordInvalid
    # Errors stay for the form; unsaved values go, so the next call can lock the row again.
    restore_attributes
    raise
  end

  # Returns the tracking code in clear in anonymous mode, the only time it exists outside the
  # declarant's hands; nil in confidential mode.
  def submit!
    with_lock do
      raise Report::InvalidTransition, "cannot submit from #{status}" unless open_draft?
      raise Report::InvalidTransition, "authorship link already cut" if confidential? && report_ownership.nil?

      code = RecoveryCode.generate_one if anonymous?
      through_lifecycle do
        update!(
          status: "submitted",
          submitted_on: Date.current.beginning_of_month,
          draft_expires_on: nil,
          draft_token_digest: nil,
          tracking_code_digest: code && Report.digest(RecoveryCode.normalize(code), purpose: :tracking_code)
        )
        report_ownership&.update!(cutoff_on: Date.current + OWNERSHIP_DAYS)
      end
      code
    end
  end

  def start_analysis!
    transition!(from: "submitted", to: "analyzing")
  end

  def ready_for_validation!
    transition!(from: "analyzing", to: "in_validation")
  end

  # Shadows ActiveModel's validate!: use valid? or save! to run the model validations.
  def validate!(analyst)
    decide!(analyst, from: %w[in_validation], to: "validated")
  end

  def reject!(analyst)
    decide!(analyst, from: %w[submitted analyzing in_validation], to: "rejected")
  end

  # True only while a lifecycle method changes the report: the ownership cutoff is frozen otherwise.
  def lifecycle_transition?
    @lifecycle_transition == true
  end

  private
    def through_lifecycle
      @lifecycle_transition = true
      yield
    ensure
      @lifecycle_transition = false
    end

    def status_changes_through_lifecycle
      errors.add(:status, :invalid) if will_save_change_to_status? && !lifecycle_transition?
    end

    def check_draft_keys!(keys, allowed)
      unexpected = keys - allowed
      raise ArgumentError, "not draft content: #{unexpected.join(", ")}" if unexpected.any?
    end

    def decide!(analyst, from:, to:)
      raise Report::NotAllowed, "only staff decide on a report" unless analyst&.staff?

      transition!(from: from, to: to) { purge_after_decision! }
    end

    # The row lock makes the check and the change atomic. The purge shares the transaction and runs
    # before the new status, while the report's content is still writable.
    def transition!(from:, to:)
      with_lock do
        raise Report::InvalidTransition, "cannot go from #{status} to #{to}" unless Array(from).include?(status)

        yield if block_given?
        through_lifecycle { update!(status: to) }
      end
    end

    # Everything that could point back to the author or quote them goes, in one transaction. Free-text
    # answers go too: only coded answers are kept.
    def purge_after_decision!
      text_codes = taxonomy_version.fields.where(kind: "text").pluck(:code)
      narrative&.purge_raw!
      casualties.each { |casualty| casualty.update!(answers: casualty.answers.except(*text_codes)) }
      report_ownership&.destroy!
      assign_attributes(answers: answers.except(*text_codes), tracking_code_digest: nil, draft_token_digest: nil)
    end
end
