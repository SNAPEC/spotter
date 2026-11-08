require "rails_helper"
require "webauthn/fake_client"

RSpec.describe Passkey, type: :model do
  let(:user) { User.create!(email: "analyste@example.com", role: "analyst") }
  let(:client) { WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin) }

  def register(user, client:)
    options = Passkey.registration_options_for(user)
    credential = client.create(challenge: options.challenge, user_verified: true)
    Passkey.register!(user: user, credential: credential.to_json, challenge: options.challenge)
  end

  def assertion_for(user, client:, **overrides)
    options = Passkey.authentication_options_for(user)
    [ client.get(challenge: options.challenge, user_verified: true, **overrides).to_json, options.challenge ]
  end

  it "stores no timestamp" do
    expect(Passkey.column_names).not_to include("created_at", "updated_at")
  end

  describe ".register!" do
    it "stores the credential id and public key of a verified attestation" do
      passkey = register(user, client: client)

      expect(passkey).to be_persisted
      expect(passkey).to have_attributes(user: user, sign_count: 0)
      expect(passkey.external_id).to be_present
      expect(passkey.public_key).to be_present
    end

    it "refuses an attestation signed over another challenge" do
      options = Passkey.registration_options_for(user)
      credential = client.create(challenge: Passkey.registration_options_for(user).challenge, user_verified: true)

      expect { Passkey.register!(user: user, credential: credential.to_json, challenge: options.challenge) }
        .to raise_error(Passkey::InvalidCredential)
      expect(user.passkeys).to be_empty
    end

    it "refuses an attestation without user verification" do
      options = Passkey.registration_options_for(user)
      credential = client.create(challenge: options.challenge, user_verified: false)

      expect { Passkey.register!(user: user, credential: credential.to_json, challenge: options.challenge) }
        .to raise_error(Passkey::InvalidCredential)
    end

    it "refuses a missing challenge or a malformed credential" do
      credential = client.create(user_verified: true).to_json

      expect { Passkey.register!(user: user, credential: credential, challenge: nil) }.to raise_error(Passkey::InvalidCredential)
      [
        "not json", "{}", "[]", "null", %("a string"),
        { type: "public-key", id: "eA", rawId: "eA", response: "nope" }.to_json,
        { type: "public-key", id: "eA", rawId: "eA", response: {} }.to_json,
        { type: "public-key", id: "eA", rawId: "eA", response: { clientDataJSON: 1, attestationObject: [] } }.to_json,
        { type: "public-key", id: "eA", rawId: "eA", response: { clientDataJSON: "@@@", attestationObject: "@@@" } }.to_json,
        { type: "public-key", id: "eA", rawId: "eA", response: { clientDataJSON: "e30", attestationObject: "AAAA" } }.to_json,
        { type: "public-key", id: "eA", rawId: "eA", response: { clientDataJSON: "AAAA", attestationObject: "AAAA" } }.to_json
      ].each do |malformed|
        expect { Passkey.register!(user: user, credential: malformed, challenge: "abc") }
          .to raise_error(Passkey::InvalidCredential), malformed
      end
    end

    it "refuses the same credential twice through the unique index, as in a concurrent double submit" do
      # An authenticator that hands out the same credential every time.
      replaying = Class.new(WebAuthn::FakeAuthenticator) do
        private def new_credential(algorithm) = (@credential ||= super)
      end
      same = WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin, authenticator: replaying.new)
      register(user, client: same)

      expect { register(user, client: same) }.to raise_error(Passkey::InvalidCredential)
      expect(Passkey.count).to eq(1)
    end
  end

  describe ".registration_options_for" do
    it "excludes the passkeys the user already has" do
      passkey = register(user, client: client)

      options = JSON.parse(Passkey.registration_options_for(user).to_json)

      expect(options["excludeCredentials"].pluck("id")).to eq([ passkey.external_id ])
      expect(options.dig("authenticatorSelection", "userVerification")).to eq("required")
    end
  end

  describe ".authenticate" do
    it "returns the passkey for a valid assertion and records the new sign count" do
      passkey = register(user, client: client)
      credential, challenge = assertion_for(user, client: client, sign_count: 7)

      expect(Passkey.authenticate(user: user, credential: credential, challenge: challenge)).to eq(passkey)
      expect(passkey.reload.sign_count).to eq(7)
    end

    it "refuses an assertion over another challenge" do
      register(user, client: client)
      credential, _challenge = assertion_for(user, client: client)

      expect(Passkey.authenticate(user: user, credential: credential, challenge: Passkey.authentication_options_for(user).challenge)).to be_nil
    end

    it "refuses another user's passkey" do
      register(user, client: client)
      other = User.create!(email: "autre@example.com", role: "analyst")
      credential, challenge = assertion_for(user, client: client)

      expect(Passkey.authenticate(user: other, credential: credential, challenge: challenge)).to be_nil
    end

    it "refuses a sign count that goes backwards, the mark of a cloned authenticator" do
      passkey = register(user, client: client)
      passkey.update!(sign_count: 10)
      credential, challenge = assertion_for(user, client: client, sign_count: 3)

      expect(Passkey.authenticate(user: user, credential: credential, challenge: challenge)).to be_nil
    end

    it "refuses a malformed credential" do
      passkey = register(user, client: client)
      not_json = { type: "public-key", id: passkey.external_id, rawId: passkey.external_id,
                   response: { clientDataJSON: "AAAA", authenticatorData: "AAAA", signature: "AAAA" } }.to_json

      [ "nope", "{}", "[]", { type: "public-key", id: "eA", rawId: "eA", response: { signature: 1 } }.to_json, not_json ].each do |malformed|
        expect(Passkey.authenticate(user: user, credential: malformed, challenge: "abc")).to be_nil
      end
    end
  end
end
