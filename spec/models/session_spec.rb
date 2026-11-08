require "rails_helper"

RSpec.describe Session, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "lea.martin@example.com") }

  it "stores neither the client IP, the user agent nor any timestamp" do
    expect(Session.column_names).not_to include("ip_address", "user_agent", "created_at", "updated_at")
  end

  it "is not passkey-verified by default" do
    expect(user.sessions.create!).not_to be_passkey_verified
  end

  it "expires at the end of the month following sign-in" do
    travel_to Date.new(2026, 11, 17) do
      expect(user.sessions.create!.expires_on).to eq(Date.new(2026, 12, 31))
    end
  end

  describe ".resume" do
    it "returns a session that expires today" do
      session = user.sessions.create!(expires_on: Date.current)

      expect(Session.resume(session.id)).to eq(session)
    end

    it "destroys and refuses an expired session" do
      session = user.sessions.create!(expires_on: Date.yesterday)

      expect(Session.resume(session.id)).to be_nil
      expect(Session.exists?(session.id)).to be(false)
    end

    it "returns nil for an unknown id" do
      expect(Session.resume(0)).to be_nil
    end
  end
end
