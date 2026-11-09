class Report < ApplicationRecord
  EVENT_TYPES = %w[accident incident near_miss].freeze
  MODES = %w[confidential anonymous].freeze
  STATUSES = %w[draft submitted analyzing in_validation validated rejected].freeze
  TAXONOMY_COLUMNS = %w[discipline environment cause severity].freeze
  DRAFT_ATTRIBUTES = %w[event_type discipline environment cause severity answers narrative_attributes casualties_attributes].freeze
  DRAFT_NARRATIVE_ATTRIBUTES = [ "raw_text", "free_text_answers", *Narrative::DEBRIEF_FIELDS ].freeze
  DRAFT_CASUALTY_ATTRIBUTES = %w[id severity answers _destroy].freeze
  # What the analyst may correct once the report is taken in charge: the codes, not the declarant's text.
  CODING_ATTRIBUTES = %w[event_type discipline environment cause severity answers].freeze
  ANONYMIZED_TEXT_MAX_LENGTH = 20_000
  DRAFT_VALIDITY = 30
  MAX_CASUALTIES = 3

  class InvalidTransition < StandardError; end
  class NotAllowed < StandardError; end
  class DigestIncomplete < StandardError; end
  class RawContentPurgeFailed < StandardError; end

  include Lifecycle

  belongs_to :taxonomy_version
  attr_readonly :taxonomy_version_id
  has_one :narrative, dependent: :destroy
  has_many :casualties, dependent: :destroy
  has_one :report_ownership, dependent: :destroy
  has_many :analyses, dependent: :destroy
  has_many :clarifications, -> { order(:position) }, dependent: :destroy

  accepts_nested_attributes_for :narrative, update_only: true
  accepts_nested_attributes_for :casualties, allow_destroy: true

  # Written by the analyst, the only text that outlives a validation: non-deterministic, like the narrative.
  encrypts :anonymized_text
  normalizes :event_type, *TAXONOMY_COLUMNS, :anonymized_text, with: ->(value) { value.presence }
  validates :anonymized_text, length: { maximum: ANONYMIZED_TEXT_MAX_LENGTH }
  validate :anonymized_text_written_through_lifecycle

  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :event_type, inclusion: { in: EVENT_TYPES }, allow_nil: true
  before_validation :cast_answers, if: -> { taxonomy_version && will_save_change_to_answers? }
  validate :taxonomy_codes_are_options, :answers_fit_taxonomy, if: :taxonomy_version
  validate :casualties_within_limit

  scope :expired_drafts, -> { where(status: "draft", draft_expires_on: ...Date.current) }
  # Anonymous reports have no one to write to: they are left alone.
  scope :awaiting_declarant_notice, -> {
    where(mode: "confidential", status: UNDER_ANALYSIS_STATUSES, declarant_notified: false, raw_content_purged: false)
      .where(id: Clarification.where(author: "analyst").select(:report_id))
  }

  # The draft token is returned in clear once, for the anonymous declarant's cookie. A confidential
  # draft is found through its ownership instead, so it gets no token.
  def self.start_draft!(mode:, user: nil)
    raise ArgumentError, "unknown mode" unless MODES.include?(mode)
    raise ArgumentError, "a confidential draft needs its author, an anonymous one must not have one" if (mode == "confidential") != user.present?

    token = SecureRandom.base58(43) if mode == "anonymous"
    transaction do
      report = create!(
        mode: mode,
        taxonomy_version: TaxonomyVersion.current,
        draft_expires_on: Date.current + DRAFT_VALIDITY,
        draft_token_digest: token && digest(token, purpose: :draft_token)
      )
      report.create_report_ownership!(user: user, cutoff_on: report.draft_cutoff_on) if user
      [ report, token ]
    end
  end

  def self.find_draft_by_token(token)
    return if token.blank?

    where(status: "draft", draft_expires_on: Date.current..).find_by(draft_token_digest: digest(token, purpose: :draft_token))
  end

  def self.find_by_tracking_code(code)
    normalized = RecoveryCode.normalize(code)
    return if normalized.empty?

    find_by(tracking_code_digest: digest(normalized, purpose: :tracking_code))
  end

  def self.owned_by(user)
    where(id: ReportOwnership.of(user).live.select(:report_id))
  end

  # HMAC rather than a slow hash: tokens and codes are random with high entropy, and a deterministic
  # digest lets them be looked up. The purpose keys each kind separately.
  def self.digest(secret, purpose:)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.key_generator.generate_key("report_#{purpose}", 32), secret.to_s)
  end

  # The day after the last editable day, the date goes: kept longer, it would only date the submission.
  def self.close_expired_edit_windows
    where(editable_until: ...Date.current).update_all(editable_until: nil)
  end

  # A report whose analysis job was lost would wait for nothing. Reports carry no time of submission, so
  # this runs once a day at a fixed hour; a job still running for a report enqueued just before is
  # harmless, the analyzer writes once per revision.
  def self.requeue_stalled_analyses
    where(status: %w[submitted analyzing]).where.not(id: Analysis.select(:report_id)).find_each do |report|
      AnalyzeReportJob.perform_later(report, report.content_revision)
    end
  end

  # Destroying under the row lock: a draft saved meanwhile has a new expiry and is kept.
  def self.purge_expired_drafts
    expired_drafts.find_each do |report|
      report.with_lock { report.destroy! if report.expired_draft? }
    end
  end

  def confidential?
    mode == "confidential"
  end

  def anonymous?
    mode == "anonymous"
  end

  # The state conditions of edit_submitted!, with no identity involved.
  def editable_by_declarant?
    under_analysis? && !taken_in_charge? && !raw_content_purged? && editable_until.present? && editable_until >= Date.current
  end

  def open_draft?
    draft? && draft_expires_on >= Date.current
  end

  def expired_draft?
    draft? && draft_expires_on < Date.current
  end

  # No mail leaves now: its time in the mail provider's log would date the question. A report that
  # starts waiting for the declarant opens a new round for the weekly digest; a second question in a row
  # stays in the same round.
  def ask_clarification!(analyst, body)
    raise Report::NotAllowed, "only active staff ask for clarification" unless analyst&.active_staff?

    with_lock do
      # No declarant is left to answer, and the question would outlive the purge.
      raise Report::InvalidTransition, "raw content purged" if raw_content_purged?

      was_awaiting = awaiting_clarification?
      AccessLog.record!(user: analyst, report: self, action: "ask_clarification")
      add_clarification!("analyst", body).tap do
        self.declarant_notified = false unless was_awaiting
        close_editing
        save!
      end
    end
  end

  # From then on the declarant can no longer edit the report: the analyst works on a stable text. Any
  # other staff action closes editing too. A second call changes nothing and leaves no second trail.
  def take_charge!(analyst)
    raise Report::NotAllowed, "only active staff take a report in charge" unless analyst&.active_staff?

    with_lock do
      raise Report::InvalidTransition, "cannot take a #{status} report in charge" unless under_analysis?
      next if taken_in_charge?

      AccessLog.record!(user: analyst, report: self, action: "take_charge")
      close_editing
      # The declarant can no longer edit: what is blank now stays the analyst's to fill.
      prefill_blanks_from(analyses.where(status: "proposed").order(:prompt_version).last)
      save!
    end
  end

  # The report carries the final codes. A field the declarant left blank starts from the extractor's
  # proposal, and only from then on: before the take-over the declarant may still fill it, so their
  # answers and the extractor's never mix. Called under the row lock by take_charge! and by the analyzer
  # when its proposals arrive after the take-over. An unstated proposal (nil) fills nothing.
  def prefill_blanks_from(analysis)
    return unless taken_in_charge? && under_analysis? && analysis&.status == "proposed"

    proposed = analysis.proposals.to_h.filter_map { |code, proposal| [ code, proposal["value"] ] if proposal.is_a?(Hash) && !proposal["value"].nil? }.to_h
    assign_attributes(proposed.slice(*TAXONOMY_COLUMNS).select { |code, _| self[code].blank? })
    self.answers = answers.merge(proposed.except(*TAXONOMY_COLUMNS).select { |code, _| answers[code].blank? })
    save!
  end

  # The analyst corrects the codes of a report they took in charge, whatever came from the declarant or
  # the extractor. Same guards and trail as the other staff actions; answers merge like a form step.
  def correct_coding!(analyst, attrs)
    raise Report::NotAllowed, "only active staff code a report" unless analyst&.active_staff?

    attrs = attrs.to_h.deep_stringify_keys
    check_draft_keys!(attrs, CODING_ATTRIBUTES)
    write_as_analyst(analyst) { assign_attributes(merge_answers(attrs)) }
  end

  # The anonymised narrative, replaced whole. Blank clears it.
  def write_anonymized_text!(analyst, text)
    raise Report::NotAllowed, "only active staff code a report" unless analyst&.active_staff?

    write_as_analyst(analyst) { self.anonymized_text = text }
  end

  # One mail per declarant at a fixed time, whatever the number of reports and nothing of them: the mail
  # provider's log tells neither when a question was asked nor on which report. The mail carries only the
  # user. Without a live ownership or with a deactivated account, nothing is sent.
  #
  # At least once: a duplicate neutral mail costs nothing, a lost one stalls the exchange. Each user's
  # mail is queued before their reports are marked, so a failed enqueue leaves them for the next run;
  # each report is marked in its own transaction, so one report cannot hold back the others.
  def self.notify_declarants
    reports_by_user_id = awaiting_declarant_notice.find_each.select(&:awaiting_clarification?).group_by do |report|
      ReportOwnership.live.find_by(report_id: report.id)&.user_ref
    end.except(nil)

    unsent = User.active.where(id: reports_by_user_id.keys).find_each.reject do |user|
      queued = ClarificationMailer.digest(user).deliver_later
      reports_by_user_id[user.id.to_s].each(&:mark_declarant_notified) if queued
      queued
    end
    raise Report::DigestIncomplete if unsent.any?
  end

  # Called when a digest could not be delivered: the user's reports wait for the next run.
  def self.reopen_declarant_notices(user)
    where(id: ReportOwnership.live.of(user).select(:report_id), declarant_notified: true).update_all(declarant_notified: false)
  end

  def mark_declarant_notified
    with_lock do
      update_column(:declarant_notified, true) if under_analysis? && awaiting_clarification?
    end
  end

  # Authorisation comes before any state check, so a stranger learns nothing about the thread.
  def answer_clarification!(body, user: nil, tracking_code: nil)
    with_lock do
      raise Report::NotAllowed, "not the declarant of this report" unless declarant?(user: user, tracking_code: tracking_code)
      raise Report::InvalidTransition, "the analyst opens the exchange" unless clarifications.exists?(author: "analyst")

      add_clarification!("declarant", body)
    end
  end

  def awaiting_clarification?
    clarifications.reorder(position: :desc).pick(:author) == "analyst"
  end

  # The draft stays open through its expiry day: the link goes the day after, with the draft itself.
  def draft_cutoff_on
    draft_expires_on + 1
  end

  # The coded answers as they stand: the four columns and the other answers, by field code.
  def final_codes
    TAXONOMY_COLUMNS.index_with { |column| self[column] }.merge(answers)
  end

  private
    # The block assigns; nothing is written, logged or saved when it changes nothing.
    def write_as_analyst(analyst)
      with_lock do
        raise Report::InvalidTransition, "cannot code a #{status} report" unless under_analysis?
        raise Report::InvalidTransition, "take the report in charge first" unless taken_in_charge?

        yield
        next unless changed_for_autosave?

        AccessLog.record!(user: analyst, report: self, action: "code")
        through_lifecycle { save! }
      end
    rescue ActiveRecord::RecordInvalid
      restore_attributes
      raise
    end

    def anonymized_text_written_through_lifecycle
      errors.add(:anonymized_text, :invalid) if will_save_change_to_anonymized_text? && !lifecycle_transition?
    end

    def declarant?(user:, tracking_code:)
      if confidential?
        user&.active? && tracking_code.nil? && ReportOwnership.live.of(user).exists?(report_id: id)
      else
        normalized = RecoveryCode.normalize(tracking_code)
        user.nil? && normalized.present? && tracking_code_digest.present? &&
          ActiveSupport::SecurityUtils.secure_compare(Report.digest(normalized, purpose: :tracking_code), tracking_code_digest)
      end
    end

    # Called under the row lock, which also makes the position sequential.
    def add_clarification!(author, body)
      raise Report::InvalidTransition, "cannot exchange on a #{status} report" unless under_analysis?

      clarifications.create!(author: author, body: body, position: clarifications.maximum(:position).to_i + 1)
    end

    def taxonomy_codes_are_options
      TAXONOMY_COLUMNS.each do |column|
        value = self[column]
        next if value.nil? || taxonomy_version.options_for(column).any? { |option| option.code == value }

        errors.add(column, :inclusion)
      end
    end

    def cast_answers
      cast = taxonomy_version.cast_answers(answers, scope: :report)
      self.answers = cast unless cast == answers
    end

    def casualties_within_limit
      return if casualties.reject(&:marked_for_destruction?).size <= MAX_CASUALTIES

      errors.add(:casualties, :too_many, count: MAX_CASUALTIES)
    end

    def answers_fit_taxonomy
      codes = taxonomy_version.validate_answers(answers, scope: :report)
      errors.add(:answers, :invalid, codes: codes) if codes.any?
    end
end
