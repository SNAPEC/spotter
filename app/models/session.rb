class Session < ApplicationRecord
  belongs_to :user

  validate :user_is_active, on: :create
  after_create { user.postpone_purge!(session_expires_on: expires_on) }

  attribute :expires_on, :date, default: -> { Date.current.next_month.end_of_month }

  scope :expired, -> { where(expires_on: ...Date.current) }

  # Deletion belongs to PurgeExpiredSessionsJob: a GET never writes.
  def self.resume(id)
    find_by(id: id).then { |session| session unless session.nil? || session.expired? || session.user.deactivated? }
  end

  def self.purge_expired
    expired.delete_all
  end

  def expired?
    expires_on < Date.current
  end

  def may_register_passkey?
    passkey_verified? || user.passkeys.none?
  end

  def needs_enrollment_code?
    user.passkeys.none?
  end

  def passkey_registration_options!
    Passkey.registration_options_for(user).tap { |options| update_column(:webauthn_challenge, options.challenge) }
  end

  def passkey_authentication_options!
    Passkey.authentication_options_for(user).tap { |options| update_column(:webauthn_challenge, options.challenge) }
  end

  # The first passkey needs the enrollment code an admin handed over: the magic link alone is not enough.
  # Returns the recovery codes when the user had none left, else an empty array.
  #
  # The user row lock serialises enrolment with User#reset_passkeys! and User#deactivate!, which take
  # the same lock: a reset either waits and then deletes the new passkey, or wins and leaves this
  # session gone. Every check is therefore repeated under the lock.
  def register_passkey!(credential:, nickname: nil, enrollment_code: nil)
    raise Passkey::InvalidCredential, "deactivated account" if user.deactivated?
    raise Passkey::InvalidCredential, "session not verified" unless may_register_passkey?
    challenge = consume_webauthn_challenge!

    transaction do
      user.lock!
      raise Passkey::InvalidCredential, "session revoked" unless Session.exists?(id)
      raise Passkey::InvalidCredential, "deactivated account" if user.deactivated?
      raise Passkey::InvalidCredential, "session not verified" unless may_register_passkey?

      if needs_enrollment_code? && !user.consume_enrollment_code!(enrollment_code)
        raise Passkey::InvalidCredential, "invalid enrollment code"
      end

      Passkey.register!(user: user, credential: credential, challenge: challenge, nickname: nickname)
      update!(passkey_verified: true, recovered: false)
      user.recovery_codes.exists? ? [] : user.generate_recovery_codes!
    end
  end

  def verify_passkey(credential:)
    return false if user.deactivated?

    challenge = consume_webauthn_challenge!
    Passkey.authenticate(user: user, credential: credential, challenge: challenge).present? && update!(passkey_verified: true)
  end

  # A recovery code stands in for a lost passkey: the session it opens only enrols a new one.
  def verify_recovery_code(code)
    user.use_recovery_code!(code) && update!(passkey_verified: true, recovered: true)
  end

  private
    def user_is_active
      errors.add(:user, :invalid) if user&.deactivated?
    end

    # Read and cleared under a row lock, in its own transaction: a challenge serves once, even if the
    # ceremony then fails.
    def consume_webauthn_challenge!
      with_lock do
        webauthn_challenge.tap { update_column(:webauthn_challenge, nil) }
      end
    end
end
