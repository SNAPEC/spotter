require "rails_helper"

RSpec.describe PurgeExpiredSessionsJob, type: :job do
  let(:user) { User.create!(email: "lea.martin@example.com") }

  it "deletes only the sessions that expired before today, and can run again" do
    expired = user.sessions.create!(expires_on: Date.yesterday)
    last_day = user.sessions.create!(expires_on: Date.current)
    future = user.sessions.create!(expires_on: Date.tomorrow)

    2.times { described_class.perform_now }

    expect(Session.exists?(expired.id)).to be(false)
    expect(Session.where(id: [ last_day.id, future.id ]).count).to eq(2)
  end

  it "is scheduled daily at 3:00" do
    recurring = Rails.application.config_for(:recurring, env: "production")

    expect(recurring[:purge_expired_sessions]).to include(class: "PurgeExpiredSessionsJob", schedule: "every day at 3am")
  end
end
