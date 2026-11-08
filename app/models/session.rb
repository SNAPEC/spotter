class Session < ApplicationRecord
  belongs_to :user

  attribute :expires_on, :date, default: -> { Date.current.next_month.end_of_month }

  scope :expired, -> { where(expires_on: ...Date.current) }

  # Deletion belongs to PurgeExpiredSessionsJob: a GET never writes.
  def self.resume(id)
    find_by(id: id).then { |session| session unless session&.expired? }
  end

  def self.purge_expired
    expired.delete_all
  end

  def expired?
    expires_on < Date.current
  end
end
