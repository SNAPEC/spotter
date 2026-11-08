require "rails_helper"
require "webauthn/fake_client"

RSpec.describe Session, "passkey enrolment under concurrency", type: :model do
  self.use_transactional_tests = false
  after { [ AuditEvent, RecoveryCode, Passkey, Session, User ].each(&:delete_all) }

  let!(:admin) { User.create!(email: "admin@example.test", role: "admin") }
  let!(:analyst) { User.create!(email: "analyste@example.test", role: "analyst") }
  let!(:enrollment_code) { analyst.issue_enrollment_code!(by: admin) }
  let(:session) { analyst.sessions.create! }
  let(:client) { WebAuthn::FakeClient.new(Rails.configuration.x.webauthn.origin) }

  def credential
    challenge = session.passkey_registration_options!.challenge
    client.create(challenge: challenge, user_verified: true).to_json
  end

  def in_other_connection(&block)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }
  end

  def register
    session.register_passkey!(credential: credential, enrollment_code: enrollment_code)
  end

  # Session#with_lock is how the challenge gets consumed, just before the enrolment transaction.
  def after_challenge_consumed(&block)
    allow(session).to receive(:with_lock).and_wrap_original do |original, *args, &inner|
      original.call(*args, &inner).tap { in_other_connection(&block).join }
    end
  end

  it "refuses the enrolment when a reset lands between the checks and the lock" do
    after_challenge_consumed { User.find(analyst.id).reset_passkeys!(by: User.find(admin.id)) }

    expect { register }.to raise_error(Passkey::InvalidCredential, "session revoked")
    expect(analyst.passkeys.reload).to be_empty
    expect(analyst.reload.enrollment_code_digest).to be_present
  end

  it "refuses the enrolment when a deactivation lands between the checks and the lock" do
    after_challenge_consumed { User.find(analyst.id).deactivate!(by: User.find(admin.id)) }

    expect { register }.to raise_error(Passkey::InvalidCredential)
    expect(analyst.passkeys.reload).to be_empty
    expect(analyst.reload).to be_deactivated
  end

  it "makes a reset wait for an enrolment in progress, then deletes the new passkey" do
    reset = nil
    allow(Passkey).to receive(:register!).and_wrap_original do |original, **args|
      reset = in_other_connection { User.find(analyst.id).reset_passkeys!(by: User.find(admin.id)) }
      sleep 0.3
      expect(reset).to be_alive
      original.call(**args)
    end

    expect(register).not_to be_empty
    expect(reset.value).to be_present
    expect(analyst.passkeys.reload).to be_empty
    expect(analyst.recovery_codes.reload).to be_empty
    expect(analyst.sessions.reload).to be_empty
  end
end
