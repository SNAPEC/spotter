# The only link between a report and its author. Deleted at validation, at rejection, or at the cutoff.
class ReportOwnership < ApplicationRecord
  belongs_to :report

  encrypts :user_ref, deterministic: true

  validates :user_ref, :cutoff_on, presence: true

  scope :of, ->(user) { where(user_ref: user.id.to_s) }

  def self.cut_due
    where(cutoff_on: ..Date.current).delete_all
  end

  def user=(user)
    self.user_ref = user.id.to_s
  end
end
