require "rails_helper"
require "webauthn/fake_client"

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

    it "refuses an expired session but leaves its deletion to the purge job" do
      session = user.sessions.create!(expires_on: Date.yesterday)

      expect(Session.resume(session.id)).to be_nil
      expect(Session.exists?(session.id)).to be(true)
    end

    it "returns nil for an unknown id" do
      expect(Session.resume(0)).to be_nil
    end
  end

  describe "WebAuthn challenge" do
    let(:analyst) { User.create!(email: "analyste@example.com", role: "analyst") }
    let(:client) { WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin) }

    before do
      challenge = Passkey.registration_options_for(analyst).challenge
      Passkey.register!(user: analyst, credential: client.create(challenge: challenge, user_verified: true).to_json, challenge: challenge)
    end

    it "is kept on the session row, server-side" do
      session = analyst.sessions.create!

      options = session.passkey_authentication_options!

      expect(session.reload.webauthn_challenge).to eq(options.challenge)
    end

    it "verifies only once, even through two copies of the same session" do
      session = analyst.sessions.create!
      options = session.passkey_authentication_options!
      assertion = client.get(challenge: options.challenge, user_verified: true).to_json
      copy = Session.find(session.id)

      expect(session.verify_passkey(credential: assertion)).to be(true)
      copy.update_column(:passkey_verified, false)
      expect(copy.verify_passkey(credential: assertion)).to be(false)
      expect(session.reload.webauthn_challenge).to be_nil
    end
  end
end
