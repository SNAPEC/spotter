class Casualty < ApplicationRecord
  belongs_to :report

  normalizes :severity, with: ->(value) { value.presence }

  validate :severity_is_an_option, :answers_fit_taxonomy, if: -> { report&.taxonomy_version }
  validate :report_still_open
  before_destroy :refuse_once_decided

  private
    # Checked against the stored status, like Narrative: a decided report is read-only.
    def report_decided?
      Report.decided.exists?(report_id)
    end

    def report_still_open
      errors.add(:report, :invalid) if report_decided?
    end

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
