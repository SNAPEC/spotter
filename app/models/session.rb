class Session < ApplicationRecord
  belongs_to :user

  attribute :expires_on, :date, default: -> { Date.current.next_month.end_of_month }

  scope :expired, -> { where(expires_on: ...Date.current) }

  def self.resume(id)
    session = find_by(id: id)
    return session unless session&.expired?

    session.destroy
    nil
  end

  def self.purge_expired
    expired.delete_all
  end

  def expired?
    expires_on < Date.current
  end
end
