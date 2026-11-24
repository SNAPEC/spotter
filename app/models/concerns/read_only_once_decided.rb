# What hangs off a report is read-only once the report is decided, except what the decision itself
# kept. Checked against the stored status, not the loaded report: a stale copy must not let text back in.
module ReadOnlyOnceDecided
  extend ActiveSupport::Concern

  included do
    validate :report_still_open
  end

  private
    def report_decided?
      Report.decided.exists?(report_id)
    end

    # Overridden by models that keep part of their content after the decision.
    def kept_after_decision?
      false
    end

    def report_still_open
      errors.add(:report, :invalid) if report_decided? && !kept_after_decision?
    end
end
