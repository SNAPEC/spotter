require "rails_helper"
require "webauthn/fake_client"

RSpec.describe "Passkey flow", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:client) { WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin) }
  let(:analyst) { User.create!(email: "analyste@example.com", role: "analyst") }
  let(:admin) { User.create!(email: "admin@example.com", role: "admin") }
  let(:issuer) { User.create!(email: "emetteur@example.com", role: "admin") }

  def sign_in(user)
    post magic_link_path(user.reload.magic_link_token)
  end

  def register_passkey(nickname: "Ordinateur", enrollment_code: nil, authenticator: client)
    post options_passkey_registration_path, as: :json
    challenge = response.parsed_body.fetch("challenge")
    credential = authenticator.create(challenge: challenge, user_verified: true).to_json
    post passkey_registration_path, params: { credential: credential, nickname: nickname, enrollment_code: enrollment_code }.compact
  end

  def register_first_passkey(user, **options)
    register_passkey(enrollment_code: user.issue_enrollment_code!(by: issuer), **options)
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
    register_first_passkey(user)
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

      register_first_passkey(analyst)

      expect(response).to have_http_status(:ok)
      expect(analyst.passkeys.sole.nickname).to eq("Ordinateur")
      get "/analyst"
      expect(response).to have_http_status(:ok)
    end

    it "shows the 10 recovery codes once, without caching, and stores only their digests" do
      sign_in(analyst)
      register_first_passkey(analyst)

      codes = response.body.scan(/\b[a-z0-9]{5}(?:-[a-z0-9]{5}){3}\b/).uniq
      expect(codes.size).to eq(10)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(analyst.recovery_codes.count).to eq(10)
      expect(analyst.use_recovery_code!(codes.first)).to be(true)
    end

    it "keeps the session pending, and the enrollment code valid, when the attestation does not verify" do
      code = analyst.issue_enrollment_code!(by: issuer)
      sign_in(analyst)
      post options_passkey_registration_path, as: :json
      post passkey_registration_path, params: { credential: client.create(challenge: "d3Jvbmc", user_verified: true).to_json, enrollment_code: code }

      expect(response).to redirect_to(new_passkey_registration_path)
      expect(analyst.passkeys).to be_empty
      expect(analyst.reload.enrollment_code_digest).to be_present
      get "/analyst"
      expect(response).to redirect_to(new_passkey_registration_path)
    end

    it "uses each challenge once" do
      sign_in(analyst)
      post options_passkey_registration_path, as: :json
      challenge = response.parsed_body.fetch("challenge")
      code = analyst.issue_enrollment_code!(by: issuer)
      post passkey_registration_path, params: { credential: client.create(challenge: challenge, user_verified: true).to_json, enrollment_code: code }

      other_authenticator = WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin)
      post passkey_registration_path, params: { credential: other_authenticator.create(challenge: challenge, user_verified: true).to_json }

      expect(response).to redirect_to(new_passkey_registration_path)
      expect(analyst.passkeys.count).to eq(1)
    end
  end

  describe "enrollment code" do
    it "tells a staff member without a code to ask an admin" do
      sign_in(analyst)

      get new_passkey_registration_path

      expect(response.body).to include("Demandez un code d’enrôlement à un administrateur")
      expect(response.body).not_to include(%(name="credential"))
    end

    it "asks for the code together with the passkey when one was issued" do
      analyst.issue_enrollment_code!(by: issuer)
      sign_in(analyst)

      get new_passkey_registration_path

      expect(response.body).to include(%(name="enrollment_code"))
    end

    it "refuses a registration without the code or with a wrong one, and keeps the session pending" do
      analyst.issue_enrollment_code!(by: issuer)
      sign_in(analyst)

      register_passkey
      expect(response).to redirect_to(new_passkey_registration_path)
      register_passkey(enrollment_code: "aaaaa-bbbbb-ccccc-ddddd")
      expect(response).to redirect_to(new_passkey_registration_path)

      expect(analyst.passkeys).to be_empty
      get "/analyst"
      expect(response).to redirect_to(new_passkey_registration_path)
    end

    it "refuses an expired code and says to ask for a new one" do
      code = nil
      travel_to(Date.new(2026, 11, 10)) { code = analyst.issue_enrollment_code!(by: issuer) }

      travel_to(Date.new(2026, 11, 18)) do
        sign_in(analyst)
        get new_passkey_registration_path
        expect(response.body).to include("Votre code d’enrôlement a expiré")
        expect(response.body).not_to include(%(name="credential"))

        register_passkey(enrollment_code: code)
        expect(response).to redirect_to(new_passkey_registration_path)
        expect(analyst.passkeys).to be_empty
      end
    end

    it "works once" do
      code = analyst.issue_enrollment_code!(by: issuer)
      sign_in(analyst)
      register_passkey(enrollment_code: code)
      expect(analyst.passkeys.count).to eq(1)
      expect(analyst.reload.enrollment_code_digest).to be_nil

      analyst.passkeys.delete_all
      delete session_path
      sign_in(analyst)
      register_passkey(enrollment_code: code, authenticator: WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin))

      expect(response).to redirect_to(new_passkey_registration_path)
      expect(analyst.passkeys).to be_empty
    end

    it "limits the attempts per user" do
      analyst.issue_enrollment_code!(by: issuer)
      sign_in(analyst)

      5.times { register_passkey(enrollment_code: "aaaaa-bbbbb-ccccc-ddddd") }
      register_passkey(enrollment_code: "aaaaa-bbbbb-ccccc-ddddd")

      expect(response).to have_http_status(:too_many_requests)
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
      follow_redirect! while response.redirect?
      expect(response.body.scan(I18n.t("passkey_registrations.create.done")).size).to eq(1)
    end

    it "accepts a recovery code once, for this session only" do
      code = analyst.generate_recovery_codes!.first
      sign_in(analyst)

      post recovery_code_path, params: { code: code }
      expect(response).to redirect_to(new_passkey_registration_path)
      get new_passkey_registration_path
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

    it "confines a session opened with a recovery code to enrolment and sign out, until a new passkey" do
      code = analyst.generate_recovery_codes!.first
      sign_in(analyst)
      post recovery_code_path, params: { code: code }

      [ "/analyst", "/", new_passkey_session_path, new_recovery_code_path ].each do |path|
        get path
        expect(response).to redirect_to(new_passkey_registration_path)
      end
      delete sessions_path
      expect(response).to redirect_to(new_passkey_registration_path)
      expect(analyst.sessions.count).to eq(1)

      get "/analyst"
      register_passkey(nickname: "Nouvel appareil", authenticator: WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin))

      expect(response).to redirect_to("http://www.example.com/analyst")
      expect(analyst.passkeys.count).to eq(2)
      expect(analyst.sessions.sole).to have_attributes(passkey_verified: true, recovered: false)
      get "/analyst"
      expect(response).to have_http_status(:ok)
    end

    it "lets a recovered session sign out" do
      code = analyst.generate_recovery_codes!.first
      sign_in(analyst)
      post recovery_code_path, params: { code: code }

      delete session_path

      expect(response).to redirect_to(login_path)
      expect(analyst.sessions).to be_empty
    end

    it "lets a pending staff member sign out of this session, not everywhere" do
      verified = analyst.sessions.create!(passkey_verified: true)
      sign_in(analyst)

      delete sessions_path
      expect(response).to redirect_to(new_passkey_session_path)
      expect(Session.exists?(verified.id)).to be(true)

      delete session_path
      expect(response).to redirect_to(login_path)
    end

    it "does not verify a later session with a replayed assertion and an old session cookie" do
      sign_in(analyst)
      post options_passkey_session_path, as: :json
      old_rails_session = cookies["_spotter_session"]
      challenge, allowed = response.parsed_body.values_at("challenge", "allowCredentials")
      assertion = client.get(challenge: challenge, user_verified: true, sign_count: 0, allow_credentials: allowed.pluck("id")).to_json
      post passkey_session_path, params: { credential: assertion }
      delete session_path

      sign_in(analyst)
      cookies["_spotter_session"] = old_rails_session
      post passkey_session_path, params: { credential: assertion }

      expect(response).to redirect_to(new_passkey_session_path)
      get "/analyst"
      expect(response).to redirect_to(new_passkey_session_path)
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
      enrol(analyst)
      enrol(admin)
    end

    it "deletes the analyst's passkeys, records it and shows a fresh enrollment code once" do
      sign_in_with_passkey(admin)

      expect { post admin_user_passkey_reset_path(analyst) }.to change(AuditEvent, :count).by(2)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      code = response.body[/\b[a-z0-9]{5}(?:-[a-z0-9]{5}){3}\b/]
      expect(code).to be_present
      expect(analyst.passkeys.reload).to be_empty
      expect(AuditEvent.where(subject: analyst).order(:id).last(2).map(&:action)).to eq(%w[passkeys.reset enrollment_code.issued])

      delete session_path
      sign_in(analyst)
      register_passkey(enrollment_code: code, authenticator: WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin))
      expect(analyst.passkeys.count).to eq(1)
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

      expect(response.body).to include("<h1", "Administration</h1>")
      expect(response.body).to include("analyste@example.com")
      expect(response.body).to include(admin_user_passkey_reset_path(analyst))
      expect(response.body).not_to include(admin_user_passkey_reset_path(admin))
    end
  end
end
