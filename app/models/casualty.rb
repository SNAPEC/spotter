class Casualty < ApplicationRecord
  include ReadOnlyOnceDecided

  belongs_to :report

  normalizes :severity, with: ->(value) { value.presence }

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

    def answers_fit_taxonomy
      codes = taxonomy_version.validate_answers(answers, scope: :casualty)
      errors.add(:answers, :invalid, codes: codes) if codes.any?
    end
end
