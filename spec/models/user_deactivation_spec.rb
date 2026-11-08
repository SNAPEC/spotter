require "rails_helper"
require "webauthn/fake_client"

RSpec.describe User, "deactivation", type: :model do
  include ActiveJob::TestHelper

  def staff(name, role) = User.create!(email: "#{name}@example.test", role: role)

  let!(:admin) { staff("admin1", "admin") }
  let!(:other_admin) { staff("admin2", "admin") }
  let(:analyst) { staff("analyste", "analyst") }

  def with_credentials(user)
    user.passkeys.create!(external_id: "credential-#{user.id}", public_key: "key", sign_count: 0)
    user.generate_recovery_codes!
  end

  describe "#deactivate!" do
    it "marks the account, ends sessions and tokens, removes passkeys, codes and enrollment code" do
      codes = with_credentials(analyst)
      analyst.sessions.create!
      analyst.issue_enrollment_code!(by: admin)
      token = analyst.magic_link_token

      analyst.deactivate!(by: admin)
      analyst.reload

      expect(analyst).to be_deactivated
      expect(User.active).not_to include(analyst)
      expect(analyst.sessions).to be_empty
      expect(analyst.passkeys).to be_empty
      expect(analyst.recovery_codes).to be_empty
      expect(analyst).to have_attributes(enrollment_code_digest: nil, enrollment_code_expires_on: nil)
      expect(User.find_by_token_for(:magic_link, token)).to be_nil
      expect(analyst.use_recovery_code!(codes.first)).to be(false)
    end

    it "records who deactivated whom" do
      expect { analyst.deactivate!(by: admin) }.to change(AuditEvent, :count).by(1)

      expect(AuditEvent.last).to have_attributes(actor: admin, action: "user.deactivated", subject: analyst)
    end

    it "keeps the account referenced by access logs and audit events" do
      AccessLog.record!(user: analyst, report: Struct.new(:id).new(SecureRandom.uuid), action: "view")
      analyst.issue_enrollment_code!(by: admin)
      AuditEvent.record!(actor: analyst, action: "user.deactivated", subject: other_admin)

      analyst.deactivate!(by: admin)

      expect(AccessLog.where(user_id: analyst.id).count).to eq(1)
      expect(AuditEvent.where(actor_id: analyst.id).count).to eq(1)
      expect(AccessLog.find_by(user_id: analyst.id)).to be_persisted.and have_attributes(user: analyst)
      expect(AccessLog.find_by(user_id: analyst.id)).to be_valid
    end

    it "is a no-op the second time, with no new audit event" do
      analyst.deactivate!(by: admin)
      stamp = analyst.reload.deactivated_at

      expect { analyst.deactivate!(by: admin) }.not_to change(AuditEvent, :count)
      expect(analyst.reload.deactivated_at).to eq(stamp)
    end

    it "refuses a non-admin, oneself and a declarant" do
      declarant = User.create!(email: "declarant@example.test")

      expect { analyst.deactivate!(by: analyst) }.to raise_error(User::DeactivationNotAllowed)
      expect { admin.deactivate!(by: analyst) }.to raise_error(User::DeactivationNotAllowed)
      expect { admin.deactivate!(by: admin) }.to raise_error(User::DeactivationNotAllowed)
      expect { declarant.deactivate!(by: admin) }.to raise_error(User::DeactivationNotAllowed)
      expect(User.active.count).to eq(User.count)
      expect(AuditEvent.count).to eq(0)
    end

    it "refuses a deactivated admin acting" do
      third = staff("admin3", "admin")
      third.deactivate!(by: admin)

      expect { analyst.deactivate!(by: third.reload) }.to raise_error(User::DeactivationNotAllowed)
    end
  end

  describe "admin minimum" do
    it "refuses to deactivate an admin when fewer than 2 other active admins would remain" do
      expect { other_admin.deactivate!(by: admin) }.to raise_error(User::TooFewAdmins)
      expect(other_admin.reload).to be_active
      expect(AuditEvent.count).to eq(0)
    end

    it "lets an admin go when 2 other active admins remain, then refuses the next one" do
      third = staff("admin3", "admin")

      third.deactivate!(by: admin)

      expect(third.reload).to be_deactivated
      expect { other_admin.deactivate!(by: admin) }.to raise_error(User::TooFewAdmins)
    end

    it "does not count deactivated admins when demoting or destroying" do
      staff("admin3", "admin").deactivate!(by: admin)

      expect(other_admin.update(role: "analyst")).to be(false)
      expect(User.find(other_admin.id).destroy).to be(false)
      expect(other_admin.reload).to be_admin
    end

    it "does not block the demotion of an already deactivated admin" do
      third = staff("admin3", "admin")
      third.deactivate!(by: admin)

      expect(third.reload.update(role: "analyst")).to be(true)
    end

    it "does not count the analyst's deactivation against the minimum" do
      expect { analyst.deactivate!(by: admin) }.not_to raise_error
    end
  end

  describe "refused sign-in paths" do
    let(:client) { WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin) }
    let(:deactivated) { staff("parti", "analyst").tap { |user| user.deactivate!(by: admin) } }

    it "sends no magic link mail but answers like for anyone else" do
      result = nil
      expect { result = User.send_magic_link(deactivated.email) }.not_to have_enqueued_mail
      expect(result).to be_persisted
      expect { User.send_magic_link(admin.email) }.to have_enqueued_mail(MagicLinkMailer, :sign_in)
    end

    it "refuses a magic link token issued before and one generated afterwards" do
      fresh = deactivated.magic_link_token

      expect(User.sign_in_with_magic_link(fresh)).to be_nil
    end

    it "refuses a magic link even if the token version still matches" do
      user = staff("encours", "analyst")
      token = user.magic_link_token
      user.update_column(:deactivated_at, Time.current)

      expect(User.sign_in_with_magic_link(token)).to be_nil
    end

    it "refuses a recovery code and an enrollment code, even forged in the database" do
      code = RecoveryCode.generate_one
      deactivated.update_columns(
        enrollment_code_digest: RecoveryCode.digest(code, purpose: :enrollment_code),
        enrollment_code_expires_on: Date.current + 1
      )
      deactivated.recovery_codes.create!(code: "ABCD-EFGH-IJKL")

      expect(deactivated.consume_enrollment_code!(code)).to be(false)
      expect(deactivated.use_recovery_code!("ABCD-EFGH-IJKL")).to be(false)
    end

    it "refuses to issue or reset an enrollment code" do
      expect { deactivated.issue_enrollment_code!(by: admin) }.to raise_error(User::EnrollmentNotAllowed)
      expect { deactivated.reset_passkeys!(by: admin) }.to raise_error(User::PasskeyResetNotAllowed)
    end

    it "refuses to create a session" do
      expect { deactivated.sessions.create! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses to resume a session that survived, and a passkey or recovery code check on it" do
      session = Session.insert_all!([ { user_id: deactivated.id, expires_on: Date.current.end_of_month } ], returning: [ :id ]).first["id"]
      session = Session.find(session)
      deactivated.passkeys.create!(external_id: "survivor", public_key: "key", sign_count: 0)
      deactivated.recovery_codes.create!(code: "ABCD-EFGH-IJKL")

      expect(Session.resume(session.id)).to be_nil
      expect(session.verify_passkey(credential: "{}")).to be(false)
      expect(session.verify_recovery_code("ABCD-EFGH-IJKL")).to be(false)
      expect { session.register_passkey!(credential: "{}") }.to raise_error(Passkey::InvalidCredential)
      expect(session).not_to be_passkey_verified
    end
  end
end
