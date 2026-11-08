class Report < ApplicationRecord
  EVENT_TYPES = %w[accident incident near_miss].freeze
  MODES = %w[confidential anonymous].freeze
  STATUSES = %w[draft submitted analyzing in_validation validated rejected].freeze
  TAXONOMY_COLUMNS = %w[discipline environment cause severity].freeze
  DRAFT_ATTRIBUTES = %w[event_type discipline environment cause severity answers narrative_attributes casualties_attributes].freeze
  DRAFT_NARRATIVE_ATTRIBUTES = [ "raw_text", *Narrative::DEBRIEF_FIELDS ].freeze
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

  accepts_nested_attributes_for :narrative, update_only: true
  accepts_nested_attributes_for :casualties, allow_destroy: true

  normalizes :event_type, *TAXONOMY_COLUMNS, with: ->(value) { value.presence }

  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :event_type, inclusion: { in: EVENT_TYPES }, allow_nil: true
  validate :taxonomy_codes_are_options, :answers_fit_taxonomy, if: :taxonomy_version
  validate :no_free_text_once_decided, if: -> { taxonomy_version && will_save_change_to_answers? }

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

  # An overdue link is ignored even before CutOwnershipsJob deletes it.
  def self.owned_by(user)
    where(id: ReportOwnership.of(user).where(cutoff_on: Date.current.next_day..).select(:report_id))
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

  # The draft stays open through its expiry day: the link goes the day after, with the draft itself.
  def draft_cutoff_on
    draft_expires_on + 1
  end

  private
    def free_text_codes
      taxonomy_version.fields.where(kind: "text").pluck(:code)
    end

    # Checked against the stored status, like Narrative: the purge removed them, a stale copy must not
    # bring them back.
    def no_free_text_once_decided
      return unless persisted? && Report.decided.exists?(id)

      errors.add(:answers, :invalid) if answers.is_a?(Hash) && answers.keys.intersect?(free_text_codes)
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
      errors.add(:answers, :invalid, codes: codes) if codes.any?
    end
end
