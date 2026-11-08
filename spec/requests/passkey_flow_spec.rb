require "rails_helper"
require "webauthn/fake_client"

RSpec.describe "Passkey flow", type: :request do
  let(:client) { WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin) }
  let(:analyst) { User.create!(email: "analyste@example.com", role: "analyst") }
  let(:admin) { User.create!(email: "admin@example.com", role: "admin") }

  def sign_in(user)
    post magic_link_path(user.reload.magic_link_token)
  end

  def register_passkey(nickname: "Ordinateur")
    post options_passkey_registration_path, as: :json
    challenge = response.parsed_body.fetch("challenge")
    post passkey_registration_path, params: { credential: client.create(challenge: challenge, user_verified: true).to_json, nickname: nickname }
  end

  def verify_passkey
    post options_passkey_session_path, as: :json
    challenge, allowed = response.parsed_body.values_at("challenge", "allowCredentials")
    assertion = client.get(challenge: challenge, user_verified: true, allow_credentials: allowed.pluck("id"))
    post passkey_session_path, params: { credential: assertion.to_json }
  end

  def sign_in_with_passkey(user)
    sign_in(user)
    verify_passkey
  end

  def enrol(user)
    sign_in(user)
    register_passkey
    delete session_path
  end

  describe "first sign-in of a staff member" do
    it "sends an analyst without a passkey to the registration, and lets them in only after" do
      get "/analyst"
      sign_in(analyst)
      follow_redirect!

      expect(response).to redirect_to(new_passkey_registration_path)

      get "/analyst"
      expect(response).to redirect_to(new_passkey_registration_path)
      get "/"
      expect(response).to redirect_to(new_passkey_registration_path)

      register_passkey

      expect(response).to have_http_status(:ok)
      expect(analyst.passkeys.sole.nickname).to eq("Ordinateur")
      get "/analyst"
      expect(response).to have_http_status(:ok)
    end

    it "shows the 10 recovery codes once, without caching, and stores only their digests" do
      sign_in(analyst)
      register_passkey

      codes = response.body.scan(/\b[a-z0-9]{5}(?:-[a-z0-9]{5}){3}\b/).uniq
      expect(codes.size).to eq(10)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(analyst.recovery_codes.count).to eq(10)
      expect(analyst.use_recovery_code!(codes.first)).to be(true)
    end

    it "keeps the session pending when the attestation does not verify" do
      sign_in(analyst)
      post options_passkey_registration_path, as: :json
      post passkey_registration_path, params: { credential: client.create(challenge: "d3Jvbmc", user_verified: true).to_json }

      expect(response).to redirect_to(new_passkey_registration_path)
      expect(analyst.passkeys).to be_empty
      get "/analyst"
      expect(response).to redirect_to(new_passkey_registration_path)
    end

    it "uses each challenge once" do
      sign_in(analyst)
      post options_passkey_registration_path, as: :json
      challenge = response.parsed_body.fetch("challenge")
      post passkey_registration_path, params: { credential: client.create(challenge: challenge, user_verified: true).to_json }

      other_authenticator = WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin)
      post passkey_registration_path, params: { credential: other_authenticator.create(challenge: challenge, user_verified: true).to_json }

      expect(response).to redirect_to(new_passkey_registration_path)
      expect(analyst.passkeys.count).to eq(1)
    end
  end

  describe "later sign-ins" do
    before { enrol(analyst) }

    it "asks for the passkey, then lets the analyst in" do
      get "/analyst"
      sign_in(analyst)
      follow_redirect!
      expect(response).to redirect_to(new_passkey_session_path)

      verify_passkey

      expect(response).to redirect_to("http://www.example.com/analyst")
      get "/analyst"
      expect(response).to have_http_status(:ok)
    end

    it "refuses an assertion signed over another challenge" do
      sign_in(analyst)
      post options_passkey_session_path, as: :json
      post passkey_session_path, params: { credential: client.get(challenge: "d3Jvbmc", user_verified: true).to_json }

      expect(response).to redirect_to(new_passkey_session_path)
      get "/analyst"
      expect(response).to redirect_to(new_passkey_session_path)
    end

    it "does not let a pending session add a passkey" do
      sign_in(analyst)

      get new_passkey_registration_path
      expect(response).to redirect_to(new_passkey_session_path)
      post options_passkey_registration_path, as: :json
      expect(response).to redirect_to(new_passkey_session_path)
    end

    it "lets a verified session add another passkey" do
      sign_in_with_passkey(analyst)

      register_passkey(nickname: "Téléphone")

      expect(analyst.passkeys.count).to eq(2)
      expect(response).to redirect_to(root_url)
    end

    it "accepts a recovery code once, for this session only" do
      code = analyst.generate_recovery_codes!.first
      sign_in(analyst)

      post recovery_code_path, params: { code: code }
      expect(response).to redirect_to(new_passkey_registration_path)
      get "/analyst"
      expect(response).to have_http_status(:ok)

      delete session_path
      sign_in(analyst)
      get "/analyst"
      expect(response).to redirect_to(new_passkey_session_path)

      post recovery_code_path, params: { code: code }
      expect(response).to have_http_status(:unprocessable_entity)
      get "/analyst"
      expect(response).to redirect_to(new_passkey_session_path)
    end

    it "lets a pending staff member sign out" do
      sign_in(analyst)

      delete session_path

      expect(response).to redirect_to(login_path)
    end
  end

  describe "declarants" do
    let(:declarant) { User.create!(email: "moniteur@example.com") }

    it "need no passkey and cannot register one" do
      sign_in(declarant)

      get "/"
      expect(response).to have_http_status(:ok)
      get new_passkey_registration_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "admin reset" do
    before do
      User.create!(email: "admin2@example.com", role: "admin")
      enrol(analyst)
      enrol(admin)
    end

    it "deletes the analyst's passkeys and records it" do
      sign_in_with_passkey(admin)

      expect { post admin_user_passkey_reset_path(analyst) }.to change(AuditEvent, :count).by(1)

      expect(response).to redirect_to(admin_root_path)
      expect(analyst.passkeys.reload).to be_empty
      expect(AuditEvent.last).to have_attributes(actor: admin, action: "passkeys.reset", subject: analyst)
    end

    it "refuses an admin resetting their own passkeys" do
      sign_in_with_passkey(admin)

      expect { post admin_user_passkey_reset_path(admin) }.not_to change(AuditEvent, :count)

      expect(response).to redirect_to(admin_root_path)
      expect(admin.passkeys.reload).not_to be_empty
    end

    it "is closed to analysts and to pending admin sessions" do
      sign_in_with_passkey(analyst)
      post admin_user_passkey_reset_path(admin)
      expect(response).to have_http_status(:forbidden)
      delete session_path

      sign_in(admin)
      post admin_user_passkey_reset_path(analyst)
      expect(response).to redirect_to(new_passkey_session_path)
      expect(analyst.passkeys.reload).not_to be_empty
    end

    it "lists staff members with a reset button on the admin home" do
      sign_in_with_passkey(admin)

      get admin_root_path

      expect(response.body).to include("analyste@example.com")
      expect(response.body).to include(admin_user_passkey_reset_path(analyst))
      expect(response.body).not_to include(admin_user_passkey_reset_path(admin))
    end
  end
end
