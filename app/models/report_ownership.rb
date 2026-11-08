# The only link between a report and its author. Deleted at validation, at rejection, or at the cutoff.
class ReportOwnership < ApplicationRecord
  belongs_to :report

  encrypts :user_ref, deterministic: true

  validates :user_ref, :cutoff_on, presence: true
  validate :cutoff_within_lifecycle

  scope :of, ->(user) { where(user_ref: user.id.to_s) }

  def self.cut_due
    where(cutoff_on: ..Date.current).delete_all
  end

  def user=(user)
    self.user_ref = user.id.to_s
  end

  private
    # Only the lifecycle sets the cutoff; this bounds any other write to what it could have set.
    def cutoff_within_lifecycle
      return if cutoff_on.nil? || report.nil?

      limit = report.draft? ? report.draft_cutoff_on : Date.current + Report::Lifecycle::OWNERSHIP_DAYS
      errors.add(:cutoff_on, :invalid) if cutoff_on > limit
    end
end
