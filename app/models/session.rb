class Session < ApplicationRecord
  belongs_to :user

  attribute :expires_on, :date, default: -> { Date.current.next_month.end_of_month }

  scope :expired, -> { where(expires_on: ...Date.current) }

  # Deletion belongs to PurgeExpiredSessionsJob: a GET never writes.
  def self.resume(id)
    find_by(id: id).then { |session| session unless session&.expired? }
  end

  def self.purge_expired
    expired.delete_all
  end

  def expired?
    expires_on < Date.current
  end

  # A pending session may enrol only the very first passkey; the magic link alone vouches for it.
  def may_register_passkey?
    passkey_verified? || user.passkeys.none?
  end

  # Returns the recovery codes when the user had none left, else an empty array.
  def register_passkey!(credential:, challenge:, nickname: nil)
    raise Passkey::InvalidCredential, "session not verified" unless may_register_passkey?

    transaction do
      Passkey.register!(user: user, credential: credential, challenge: challenge, nickname: nickname)
      update!(passkey_verified: true)
      user.recovery_codes.exists? ? [] : user.generate_recovery_codes!
    end
  end

  def verify_passkey(credential:, challenge:)
    Passkey.authenticate(user: user, credential: credential, challenge: challenge).present? && update!(passkey_verified: true)
  end

  def verify_recovery_code(code)
    user.use_recovery_code!(code) && update!(passkey_verified: true)
  end
end
