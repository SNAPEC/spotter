class Report < ApplicationRecord
  EVENT_TYPES = %w[accident incident near_miss].freeze
  MODES = %w[confidential anonymous].freeze
  STATUSES = %w[draft submitted analyzing in_validation validated rejected].freeze
  TAXONOMY_COLUMNS = %w[discipline environment cause severity].freeze
  DRAFT_ATTRIBUTES = %w[event_type discipline environment cause severity answers narrative_attributes casualties_attributes].freeze
  DRAFT_NARRATIVE_ATTRIBUTES = [ "raw_text", "free_text_answers", *Narrative::DEBRIEF_FIELDS ].freeze
  DRAFT_CASUALTY_ATTRIBUTES = %w[id severity answers _destroy].freeze
  DRAFT_VALIDITY = 30

  class InvalidTransition < StandardError; end
  class NotAllowed < StandardError; end

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

  normalizes :event_type, *TAXONOMY_COLUMNS, with: ->(value) { value.presence }

  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :event_type, inclusion: { in: EVENT_TYPES }, allow_nil: true
  validate :taxonomy_codes_are_options, :answers_fit_taxonomy, if: :taxonomy_version

  scope :expired_drafts, -> { where(status: "draft", draft_expires_on: ...Date.current) }

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

  def open_draft?
    draft? && draft_expires_on >= Date.current
  end

  def expired_draft?
    draft? && draft_expires_on < Date.current
  end

  # The declarant is told by mail, after the commit, when the report still has a live ownership.
  def ask_clarification!(analyst, body)
    raise Report::NotAllowed, "only staff ask for clarification" unless analyst&.staff?

    with_lock do
      raise Report::InvalidTransition, "a question is already pending" if awaiting_clarification?

      AccessLog.record!(user: analyst, report: self, action: "ask_clarification")
      add_clarification!("analyst", body).tap do
        ActiveRecord.after_all_transactions_commit { ClarificationMailer.requested(self).deliver_later }
      end
    end
  end

  def answer_clarification!(body)
    with_lock do
      raise Report::InvalidTransition, "no pending question" unless awaiting_clarification?

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

  private
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

    def answers_fit_taxonomy
      codes = taxonomy_version.validate_answers(answers, scope: :report)
      codes += answers.keys.map(&:to_s).intersection(taxonomy_version.free_text_codes).map { |code| "#{code}.free_text" } if answers.is_a?(Hash)
      errors.add(:answers, :invalid, codes: codes) if codes.any?
    end
end
