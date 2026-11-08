require "rails_helper"

RSpec.describe User, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "lea.martin@example.com") }

  it "stores no password and no timestamp" do
    expect(User.column_names).not_to include("password_digest", "created_at", "updated_at")
  end

  it "defaults to the declarant role" do
    expect(user.role).to eq("declarant")
  end

  it "rejects an unknown role in the model and in the database" do
    expect(User.new(email: "x@example.com", role: "boss")).not_to be_valid
    expect { user.update_column(:role, "boss") }.to raise_error(ActiveRecord::StatementInvalid, /users_role_check/)
  end

  it "rejects a malformed email" do
    expect(User.new(email: "not an email")).not_to be_valid
  end

  describe "email encryption" do
    it "does not store the email in clear" do
      raw = User.connection.select_value(User.where(id: user.id).select(:email).to_sql)

      expect(raw).not_to include("example.com")
    end

    it "finds a user by email regardless of case and surrounding spaces" do
      user

      expect(User.find_by(email: "  Lea.Martin@EXAMPLE.com ")).to eq(user)
    end
  end

  describe "roles" do
    it "tells staff apart from declarants" do
      expect(user).not_to be_staff
      expect(User.new(role: "analyst")).to be_analyst.and be_staff
      expect(User.new(role: "admin")).to be_admin.and be_staff
    end
  end

  describe "#member?" do
    it "is true until the membership expiry date included" do
      user.membership_expires_on = Date.current

      expect(user).to be_member
    end

    it "is false once the membership has expired or without a date" do
      user.membership_expires_on = Date.yesterday
      expect(user).not_to be_member

      user.membership_expires_on = nil
      expect(user).not_to be_member
    end
  end

  describe "magic link" do
    it "finds the user from a fresh token" do
      expect(User.find_by_token_for(:magic_link, user.magic_link_token)).to eq(user)
    end

    it "expires the token after 15 minutes" do
      token = user.magic_link_token

      travel 15.minutes + 1.second do
        expect(User.find_by_token_for(:magic_link, token)).to be_nil
      end
    end

    it "invalidates the token once consumed" do
      token = user.magic_link_token

      expect(user.consume_magic_link!).to be(true)
      expect(User.find_by_token_for(:magic_link, token)).to be_nil
    end

    it "lets only one of two concurrent consumers win" do
      other_copy = User.find(user.id)

      expect(user.consume_magic_link!).to be(true)
      expect(other_copy.consume_magic_link!).to be(false)
    end

    describe ".sign_in_with_magic_link" do
      it "returns the user once and refuses the same token afterwards" do
        token = user.magic_link_token

        expect(User.sign_in_with_magic_link(token)).to eq(user)
        expect(User.sign_in_with_magic_link(token)).to be_nil
      end

      it "refuses a tampered token" do
        expect(User.sign_in_with_magic_link("#{user.magic_link_token}x")).to be_nil
      end
    end
  end

  describe "#sign_out_everywhere!" do
    it "destroys every session and invalidates pending magic links" do
      2.times { user.sessions.create! }
      token = user.magic_link_token

      user.sign_out_everywhere!

      expect(user.sessions.reload).to be_empty
      expect(User.find_by_token_for(:magic_link, token)).to be_nil
    end
  end

  describe ".send_magic_link" do
    include ActionMailer::TestHelper

    it "creates a declarant for an unknown email and mails the link" do
      user = nil

      assert_enqueued_emails(1) { user = User.send_magic_link("nouveau@example.com") }
      expect(user).to be_persisted.and have_attributes(role: "declarant")
    end

    it "reuses the account of a known email" do
      user

      expect { expect(User.send_magic_link("LEA.MARTIN@example.com")).to eq(user) }.not_to change(User, :count)
    end

    it "sends nothing for a malformed email" do
      assert_no_enqueued_emails { expect(User.send_magic_link("nope")).not_to be_persisted }
    end
  end

  describe "admin count" do
    def admin(name) = User.create!(email: "#{name}@example.com", role: "admin")

    it "refuses to demote an admin when fewer than 2 admins would remain" do
      first, _second = admin("admin1"), admin("admin2")

      first.role = "analyst"

      expect(first).not_to be_valid
      expect(first.errors[:role]).to be_present
      expect { first.save }.not_to change { User.admin.count }
    end

    it "lets an admin go when at least 2 others remain" do
      first, _second, _third = admin("admin1"), admin("admin2"), admin("admin3")

      expect(first.update(role: "analyst")).to be(true)
    end

    it "refuses to destroy an admin when fewer than 2 admins would remain" do
      first, _second = admin("admin1"), admin("admin2")

      expect(first.destroy).to be(false)
      expect(User.admin.count).to eq(2)
      expect(first.errors[:base]).to be_present
    end

    it "lets an admin be destroyed when at least 2 others remain" do
      first, _second, _third = admin("admin1"), admin("admin2"), admin("admin3")

      expect(first.destroy).to be_truthy
    end

    it "does not get in the way of other changes" do
      solo = admin("solo")

      expect(solo.update(membership_expires_on: Date.current)).to be(true)
      expect(user.update(role: "analyst")).to be(true)
    end
  end

  describe "#reset_passkeys!" do
    let(:admin) { User.create!(email: "admin@example.com", role: "admin") }
    let(:analyst) { User.create!(email: "analyste@example.com", role: "analyst") }

    before do
      analyst.passkeys.create!(external_id: "credential-1", public_key: "key", sign_count: 0)
      analyst.generate_recovery_codes!
      analyst.sessions.create!(passkey_verified: true)
    end

    it "deletes passkeys, recovery codes and sessions, and records who did it" do
      expect { analyst.reset_passkeys!(by: admin) }.to change(AuditEvent, :count).by(2)

      expect(analyst.passkeys.reload).to be_empty
      expect(analyst.recovery_codes.reload).to be_empty
      expect(analyst.sessions.reload).to be_empty
      expect(AuditEvent.find_by(action: "passkeys.reset")).to have_attributes(actor: admin, subject: analyst)
    end

    it "refuses an admin resetting their own passkeys" do
      admin.passkeys.create!(external_id: "credential-2", public_key: "key", sign_count: 0)

      expect { admin.reset_passkeys!(by: admin) }.to raise_error(User::PasskeyResetNotAllowed)
      expect(admin.passkeys.reload.size).to eq(1)
      expect(AuditEvent.count).to eq(0)
    end

    it "refuses a user who is not staff, without auditing or signing them out" do
      declarant = User.create!(email: "moniteur@example.com")
      declarant.sessions.create!

      expect { declarant.reset_passkeys!(by: admin) }.to raise_error(User::PasskeyResetNotAllowed)
      expect(declarant.sessions.reload.size).to eq(1)
      expect(AuditEvent.count).to eq(0)
    end

    it "issues an enrollment code and returns it" do
      code = analyst.reset_passkeys!(by: admin)

      expect(analyst.reload.enrollment_code_digest).to be_present
      expect(analyst.enrollment_code_digest).not_to include(code.delete("-"))
    end

    it "refuses a non-admin" do
      other = User.create!(email: "autre@example.com", role: "analyst")

      expect { analyst.reset_passkeys!(by: other) }.to raise_error(User::PasskeyResetNotAllowed)
      expect(analyst.passkeys.reload.size).to eq(1)
    end
  end

  describe "#issue_enrollment_code!" do
    let(:admin) { User.create!(email: "admin@example.com", role: "admin") }
    let(:analyst) { User.create!(email: "analyste@example.com", role: "analyst") }

    it "returns the code once, stores only a digest and records who issued it" do
      code = nil

      expect { code = analyst.issue_enrollment_code!(by: admin) }.to change(AuditEvent, :count).by(1)

      expect(code).to match(/\A[a-z0-9]{5}(-[a-z0-9]{5}){3}\z/)
      raw = User.connection.select_value("SELECT enrollment_code_digest FROM users WHERE id = #{analyst.id}")
      expect(raw).to be_present
      expect(raw).not_to include(code.delete("-"))
      expect(AuditEvent.last).to have_attributes(actor: admin, action: "enrollment_code.issued", subject: analyst)
    end

    it "replaces the previous code" do
      old_code = analyst.issue_enrollment_code!(by: admin)
      new_code = analyst.issue_enrollment_code!(by: admin)

      expect(analyst.enrollment_code_digest).to eq(RecoveryCode.digest(new_code, purpose: :enrollment_code))
      expect(analyst.enrollment_code_digest).not_to eq(RecoveryCode.digest(old_code, purpose: :enrollment_code))
    end

    it "lets an admin bootstrap their own enrollment from the console" do
      expect { admin.issue_enrollment_code!(by: admin) }.not_to raise_error
    end

    it "refuses a non-admin issuer and a non-staff user" do
      declarant = User.create!(email: "moniteur@example.com")

      expect { analyst.issue_enrollment_code!(by: User.create!(email: "autre@example.com", role: "analyst")) }
        .to raise_error(User::EnrollmentNotAllowed)
      expect { declarant.issue_enrollment_code!(by: admin) }.to raise_error(User::EnrollmentNotAllowed)
    end
  end
end
