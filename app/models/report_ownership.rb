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
    # Deletion dates are the same for everyone: a draft's link follows its expiry, and once submitted
    # the cutoff set by submit! is frozen.
    def cutoff_within_lifecycle
      return if cutoff_on.nil? || report.nil?

      if report.draft?
        errors.add(:cutoff_on, :invalid) unless cutoff_on == report.draft_cutoff_on
      elsif (new_record? || will_save_change_to_cutoff_on?) && !report.lifecycle_transition?
        errors.add(:cutoff_on, :invalid)
      end
    end
end
