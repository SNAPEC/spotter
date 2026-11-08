# One message of the exchange between an analyst and the declarant about a report under analysis.
class Clarification < ApplicationRecord
  AUTHORS = %w[analyst declarant].freeze

  belongs_to :report

  encrypts :body

  validates :author, inclusion: { in: AUTHORS }
  validates :body, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validate :report_still_open

  private
    # Checked against the stored status, like Narrative: a decided report is read-only.
    def report_still_open
      errors.add(:report, :invalid) if Report.decided.exists?(report_id)
    end
end
