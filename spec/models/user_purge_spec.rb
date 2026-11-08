require "rails_helper"

RSpec.describe User, "purge of unused accounts", type: :model do
  let(:user) { User.create!(email: "moniteur@example.test").tap { |user| user.update_columns(purge_on: Date.current.prev_month.end_of_month) } }

  it "checks again under the lock: a sign-in since the account was loaded keeps it" do
    stale = User.purge_due.find(user.id)
    User.find(user.id).sessions.create!

    stale.purge_if_unused!

    expect(User.exists?(user.id)).to be(true)
  end

  it "checks again under the lock: a promotion since the account was loaded keeps it" do
    stale = User.purge_due.find(user.id)
    User.find(user.id).update!(role: "analyst")

    stale.purge_if_unused!

    expect(User.exists?(user.id)).to be(true)
  end

  it "keeps every date at the end of a month, in the database too" do
    expect { user.update_columns(purge_on: Date.new(2027, 3, 15)) }.to raise_error(ActiveRecord::StatementInvalid, /purge_on_end_of_month/)
  end
end
