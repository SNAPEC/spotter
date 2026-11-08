# Which staff member acted on which report. It links staff to reports, never an author. The report is
# not a foreign key: the trail outlives a purged report. Only the month is kept: an exact time could be
# matched against the mail provider's log.
class AccessLog < ApplicationRecord
  ACTIONS = %w[view ask_clarification validate reject].freeze

  belongs_to :user

  validates :action, inclusion: { in: ACTIONS }
  validate :user_is_staff

  def self.record!(user:, report:, action:)
    create!(user: user, report_id: report.id, action: action, recorded_on: Date.current.beginning_of_month)
  end

  private
    def user_is_staff
      errors.add(:user, :invalid) unless user&.staff?
    end
end
