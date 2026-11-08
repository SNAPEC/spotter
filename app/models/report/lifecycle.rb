module Report::Lifecycle
  extend ActiveSupport::Concern

  OWNERSHIP_DAYS = 60
  # A report still undecided this long after its submission month loses its raw content all the same.
  RAW_CONTENT_DAYS = 180
  DECIDED_STATUSES = %w[validated rejected].freeze
  UNDER_ANALYSIS_STATUSES = %w[submitted analyzing in_validation].freeze

  included do
    Report::STATUSES.each do |status|
      define_method(:"#{status}?") { self.status == status }
    end

    scope :decided, -> { where(status: DECIDED_STATUSES) }
    # submitted_on is the first of the month: counting from it, the purge never comes later than RAW_CONTENT_DAYS.
    scope :raw_content_overdue, -> {
      where(status: UNDER_ANALYSIS_STATUSES, raw_content_purged: false, submitted_on: ..(Date.current - RAW_CONTENT_DAYS))
    }
    validate :status_changes_through_lifecycle
  end

  # Only the content of the form: state, dates and digests stay in the lifecycle's hands.
  def save_draft!(attrs)
    attrs = form_content(attrs)

    with_lock do
      raise Report::InvalidTransition, "not an open draft" unless open_draft?

      assign_attributes(merge_answers(attrs))
      self.draft_expires_on = Date.current + Report::DRAFT_VALIDITY
      save!
      report_ownership&.update!(cutoff_on: draft_cutoff_on)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
    # Errors stay for the form; unsaved values go, so the next call can lock the row again.
    restore_attributes
    raise
  end

  # The declarant may correct a submitted report until staff take it in charge, and while the authorship
  # link would still be live (editable_until is the day before its cutoff), in both modes. A change to the
  # text the extractor reads sends the report back to analysis: the analyses go, their excerpts quote the
  # old text, and the new revision makes a run still working on the old text write nothing. Ownership
  # cutoff, tracking code and submission month stay as submit! set them.
  # Authorisation comes before any state check, so a stranger learns nothing about the report.
  def edit_submitted!(attrs, user: nil, tracking_code: nil)
    attrs = form_content(attrs)

    with_lock do
      raise Report::NotAllowed, "not the declarant of this report" unless declarant?(user: user, tracking_code: tracking_code)
      raise Report::InvalidTransition, "cannot edit a #{status} report" unless under_analysis?
      raise Report::InvalidTransition, "already taken in charge" if taken_in_charge?
      raise Report::InvalidTransition, "raw content purged" if raw_content_purged?
      raise Report::InvalidTransition, "editing window closed" unless editable_until && editable_until >= Date.current

      analyzer = Report::Analyzer.new
      analyzed_text = analyzer.text_of(self)
      assign_attributes(merge_answers(attrs))
      # A form sent back unchanged writes nothing.
      next unless changed_for_autosave?
      # Coded fields, casualties and free-text answers never reach the extractor: they keep the analysis.
      next save! if analyzer.text_of(self) == analyzed_text

      self.content_revision += 1
      through_lifecycle do
        self.status = "submitted"
        save!
      end
      analyses.destroy_all
      AnalyzeReportJob.perform_later(self, content_revision)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
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
          editable_until: Date.current + OWNERSHIP_DAYS - 1,
          draft_expires_on: nil,
          draft_token_digest: nil,
          tracking_code_digest: code && Report.digest(RecoveryCode.normalize(code), purpose: :tracking_code)
        )
        report_ownership&.update!(cutoff_on: Date.current + OWNERSHIP_DAYS)
      end
      AnalyzeReportJob.perform_later(self, content_revision)
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

  class_methods do
    # One report that cannot be purged must not keep the others' content: it is reported, by error class
    # and id only (a message may quote the narrative), and tried again the next day.
    def purge_overdue_raw_content
      raw_content_overdue.find_each do |report|
        report.purge_overdue_raw_content!
      rescue StandardError => error
        Rails.error.report(Report::RawContentPurgeFailed.new("#{error.class.name} on report #{report.id}"), handled: true)
      end
    end
  end

  # Same purge as a decision, status left as is: the analyst can still code the report by hand and decide.
  # Checked again under the row lock, so a report decided meanwhile is left alone.
  def purge_overdue_raw_content!
    with_lock do
      next unless Report.raw_content_overdue.exists?(id)

      purge_raw_content
      # The status stays: a new revision makes an analysis still running on the purged text write
      # nothing, its excerpts would bring the text back. A decision changes the status instead.
      self.content_revision += 1
      # Only purge flags change here: a report whose content no longer passes the current checks is purged all the same.
      save!(validate: false)
    end
  end

  def under_analysis?
    UNDER_ANALYSIS_STATUSES.include?(status)
  end

  # True only while a lifecycle method changes the report: the ownership cutoff is frozen otherwise.
  def lifecycle_transition?
    @lifecycle_transition == true
  end

  private
    # editable_until gives away the exact submission day: it goes as soon as editing closes.
    def close_editing
      self.taken_in_charge = true
      self.editable_until = nil
    end

    def through_lifecycle
      @lifecycle_transition = true
      yield
    ensure
      @lifecycle_transition = false
    end

    def status_changes_through_lifecycle
      errors.add(:status, :invalid) if will_save_change_to_status? && !lifecycle_transition?
    end

    def form_content(attrs)
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
      attrs
    end

    # A step of the form posts only its own answers: they are merged into the stored ones. A key posted
    # blank removes its answer, a key not posted stays. Called under the row lock, on the stored values.
    def merge_answers(attrs)
      attrs = attrs.deep_dup
      attrs["answers"] = merged_answers(answers, attrs["answers"], scope: :report) if attrs.key?("answers")
      narrative_attrs = attrs["narrative_attributes"]
      if narrative_attrs&.key?("free_text_answers") && narrative_attrs["free_text_answers"].is_a?(Hash)
        narrative_attrs["free_text_answers"] = (narrative&.free_text_answers || {}).merge(narrative_attrs["free_text_answers"])
        narrative_attrs["free_text_answers"].reject! { |_code, answer| answer.nil? || (answer.is_a?(String) && answer.blank?) }
      end
      attrs
    end

    def merged_answers(stored, posted, scope:)
      return posted unless posted.is_a?(Hash) && stored.is_a?(Hash)

      taxonomy_version.cast_answers(stored.merge(posted), scope: scope)
    end

    def check_draft_keys!(attrs, allowed)
      raise ArgumentError, "draft content must be a hash" unless attrs.is_a?(Hash)

      unexpected = attrs.keys - allowed
      raise ArgumentError, "not draft content: #{unexpected.join(", ")}" if unexpected.any?
    end

    # The access trail is written here, in the decision's transaction, so no screen can forget it.
    def decide!(analyst, from:, to:, action:)
      raise Report::NotAllowed, "only active staff decide on a report" unless analyst&.active_staff?

      transition!(from: from, to: to) do
        AccessLog.record!(user: analyst, report: self, action: action)
        close_editing
        purge_raw_content
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

    # Everything that could point back to the author or quote them goes, in the caller's transaction.
    # Free-text answers, clarifications and the extractor's excerpts go too: only coded answers are kept.
    # taken_in_charge stays: it says nothing of the author. The caller saves the report.
    def purge_raw_content
      narrative&.purge_raw!
      clarifications.destroy_all
      analyses.each(&:strip_raw_excerpts!)
      # A row's xmin is the id of the transaction that last wrote it, and ids grow with time: left as is,
      # a casualty would date the declarant's last entry. The no-op write stamps it with the purge's.
      casualties.update_all("severity = severity")
      report_ownership&.destroy!
      assign_attributes(
        tracking_code_digest: nil, draft_token_digest: nil, declarant_notified: false, editable_until: nil, raw_content_purged: true
      )
    end
end
