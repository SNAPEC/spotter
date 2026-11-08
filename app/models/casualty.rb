class Casualty < ApplicationRecord
  include ReadOnlyOnceDecided

  belongs_to :report

  normalizes :severity, with: ->(value) { value.presence }

  before_validation :cast_answers, if: -> { report&.taxonomy_version && will_save_change_to_answers? }
  validate :severity_is_an_option, :answers_fit_taxonomy, if: -> { report&.taxonomy_version }
  before_destroy :refuse_once_decided

  private
    def refuse_once_decided
      return unless report_decided?

      errors.add(:report, :invalid)
      throw :abort
    end

    def taxonomy_version
      report.taxonomy_version
    end

    def severity_is_an_option
      return if severity.nil? || taxonomy_version.options_for("severity").any? { |option| option.code == severity }

      errors.add(:severity, :inclusion)
    end

    def cast_answers
      cast = taxonomy_version.cast_answers(answers, scope: :casualty)
      self.answers = cast unless cast == answers
    end

    def answers_fit_taxonomy
      codes = taxonomy_version.validate_answers(answers, scope: :casualty)
      errors.add(:answers, :invalid, codes: codes) if codes.any?
    end
end
