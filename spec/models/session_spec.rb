require "rails_helper"

RSpec.describe Session, type: :model do
  it "stores neither the client IP, the user agent nor any timestamp" do
    expect(Session.column_names).not_to include("ip_address", "user_agent", "created_at", "updated_at")
  end

  it "is not passkey-verified by default" do
    user = User.create!(email: "lea.martin@example.com")

    expect(user.sessions.create!).not_to be_passkey_verified
  end
end
