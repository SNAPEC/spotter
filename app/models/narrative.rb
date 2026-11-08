class Narrative < ApplicationRecord
  include ReadOnlyOnceDecided

  # The five debriefing questions of taxonomy v0: what led to the event, what worked, what to do
  # differently, what already changed in practice, message to other instructors.
  DEBRIEF_FIELDS = %w[debrief_causes debrief_what_worked debrief_do_differently debrief_changes_made debrief_message].freeze
  RAW_TEXT_MAX_LENGTH = 20_000
  DEBRIEF_MAX_LENGTH = 5_000
  FREE_TEXT_ANSWER_MAX_LENGTH = 5_000

  belongs_to :report

  # Answers to the taxonomy's free-text fields, code => string: they live here, encrypted like the
  # narrative they quote, never in Report#answers.
  serialize :free_text_answers, coder: JSON
  attribute :free_text_answers, default: -> { {} }
  encrypts :raw_text, :free_text_answers, *DEBRIEF_FIELDS

  validates :raw_text, length: { maximum: RAW_TEXT_MAX_LENGTH }
  validates(*DEBRIEF_FIELDS, length: { maximum: DEBRIEF_MAX_LENGTH })
  validate :free_text_answers_fit_taxonomy, if: -> { report&.taxonomy_version }

  def purge_raw!
    update!(raw_text: nil, free_text_answers: {}, **DEBRIEF_FIELDS.index_with(nil))
  end

  private
    def kept_after_decision?
      free_text_answers.blank? && [ "raw_text", *DEBRIEF_FIELDS ].all? { |field| self[field].nil? }
    end

    def free_text_answers_fit_taxonomy
      answers = free_text_answers || {}
      return errors.add(:free_text_answers, :invalid) unless answers.is_a?(Hash)

      known = report.taxonomy_version.free_text_codes(scope: :report)
      invalid = answers.keys.map(&:to_s) - known
      return errors.add(:free_text_answers, :invalid, codes: invalid) if invalid.any? || !answers.values.all?(String)

      too_long = answers.values.any? { |answer| answer.length > FREE_TEXT_ANSWER_MAX_LENGTH }
      errors.add(:free_text_answers, :too_long, count: FREE_TEXT_ANSWER_MAX_LENGTH) if too_long
    end
end
