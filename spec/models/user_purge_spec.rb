require "rails_helper"

RSpec.describe User, "purge of unused accounts", type: :model do
  let!(:user) { User.create!(email: "moniteur@example.test").tap { |user| user.update_columns(purge_on: Date.current.beginning_of_quarter.prev_day) } }

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

  it "reports a failing account by error class only and goes on" do
    reports = []
    subscriber = Class.new do
      define_method(:report) { |error, **| reports << error }
    end.new
    Rails.error.subscribe(subscriber)
    failing = Object.new.tap { |account| account.define_singleton_method(:purge_if_unused!) { raise ActiveRecord::StatementInvalid, "secret detail" } }
    allow(User).to receive(:purge_due).and_return(double(find_each: nil).tap { |due| allow(due).to receive(:find_each).and_yield(failing) })

    expect { User.purge_unused }.not_to raise_error

    expect(reports.map(&:class)).to eq([ User::PurgeFailure ])
    expect(reports.first.message).to eq("ActiveRecord::StatementInvalid")
    expect(reports.first.message).not_to include("secret")
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  it "keeps every date at the end of a quarter, in the database too" do
    [ Date.new(2027, 3, 15), Date.new(2027, 4, 30) ].each do |date|
      expect { User.transaction(requires_new: true) { user.update_columns(purge_on: date) } }
        .to raise_error(ActiveRecord::StatementInvalid, /purge_on_end_of_quarter/)
    end
    expect { user.update_columns(purge_on: Date.new(2027, 6, 30)) }.not_to raise_error
  end

  it "starts no session for an account purged since it was loaded" do
    stale = User.find(user.id)
    user.purge_if_unused!

    expect(stale.start_session!).to be_nil
    expect(Session.where(user_id: user.id)).to be_empty
  end
end
