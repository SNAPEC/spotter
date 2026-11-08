module Report::Lifecycle
  extend ActiveSupport::Concern

  OWNERSHIP_DAYS = 60
  DECIDED_STATUSES = %w[validated rejected].freeze
  UNDER_ANALYSIS_STATUSES = %w[submitted analyzing in_validation].freeze

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
    check_draft_keys!(attrs, Report::DRAFT_ATTRIBUTES)
    check_draft_keys!(attrs["narrative_attributes"], Report::DRAFT_NARRATIVE_ATTRIBUTES) if attrs.key?("narrative_attributes")
    if attrs.key?("casualties_attributes")
      casualties = attrs["casualties_attributes"]
      raise ArgumentError, "casualties must be a list or a hash" unless casualties.is_a?(Hash) || casualties.is_a?(Array)

      (casualties.is_a?(Hash) ? casualties.values : casualties).each do |casualty|
        check_draft_keys!(casualty, Report::DRAFT_CASUALTY_ATTRIBUTES)
      end
    end

    with_lock do
      raise Report::InvalidTransition, "not an open draft" unless open_draft?

      assign_attributes(attrs)
      self.draft_expires_on = Date.current + Report::DRAFT_VALIDITY
      save!
      report_ownership&.update!(cutoff_on: draft_cutoff_on)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
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
      AnalyzeReportJob.perform_later(self)
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
    decide!(analyst, from: %w[in_validation], to: "validated", action: "validate")
  end

  def reject!(analyst)
    decide!(analyst, from: UNDER_ANALYSIS_STATUSES, to: "rejected", action: "reject")
  end

  def under_analysis?
    UNDER_ANALYSIS_STATUSES.include?(status)
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

    def check_draft_keys!(attrs, allowed)
      raise ArgumentError, "draft content must be a hash" unless attrs.is_a?(Hash)

      unexpected = attrs.keys - allowed
      raise ArgumentError, "not draft content: #{unexpected.join(", ")}" if unexpected.any?
    end

    # The access trail is written here, in the decision's transaction, so no screen can forget it.
    def decide!(analyst, from:, to:, action:)
      raise Report::NotAllowed, "only staff decide on a report" unless analyst&.staff?

      transition!(from: from, to: to) do
        AccessLog.record!(user: analyst, report: self, action: action)
        purge_after_decision!
      end
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
    # answers, clarifications and the extractor's excerpts go too: only coded answers are kept.
    def purge_after_decision!
      text_codes = free_text_codes
      narrative&.purge_raw!
      clarifications.destroy_all
      analyses.each(&:strip_raw_excerpts!)
      casualties.each { |casualty| casualty.update!(answers: casualty.answers.except(*text_codes)) }
      report_ownership&.destroy!
      assign_attributes(answers: answers.except(*text_codes), tracking_code_digest: nil, draft_token_digest: nil)
    end
end
