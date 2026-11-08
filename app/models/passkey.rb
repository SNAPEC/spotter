class Passkey < ApplicationRecord
  class InvalidCredential < StandardError; end

  # Malformed browser input surfaces as any of these before WebAuthn gets to verify it.
  MALFORMED_INPUT = [ WebAuthn::Error, JSON::ParserError, ArgumentError, TypeError, NoMethodError, KeyError ].freeze

  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true

  def self.registration_options_for(user)
    WebAuthn::Credential.options_for_create(
      user: { id: WebAuthn.configuration.encoder.encode(user.id.to_s), name: user.email, display_name: user.email },
      exclude: user.passkeys.pluck(:external_id),
      authenticator_selection: { user_verification: "required", resident_key: "preferred" }
    )
  end

  def self.authentication_options_for(user)
    WebAuthn::Credential.options_for_get(allow: user.passkeys.pluck(:external_id), user_verification: "required")
  end

  def self.register!(user:, credential:, challenge:, nickname: nil)
    attestation = WebAuthn::Credential.from_create(JSON.parse(credential))
    attestation.verify(challenge, user_verification: true)

    user.passkeys.create!(
      external_id: attestation.id,
      public_key: attestation.public_key,
      sign_count: attestation.sign_count,
      nickname: nickname.presence
    )
  rescue *MALFORMED_INPUT, ActiveRecord::RecordInvalid => error
    raise InvalidCredential, error.class.name
  end

  def self.authenticate(user:, credential:, challenge:)
    assertion = WebAuthn::Credential.from_get(JSON.parse(credential))
    passkey = user.passkeys.find_by(external_id: assertion.id)
    return unless passkey

    assertion.verify(challenge, public_key: passkey.public_key, sign_count: passkey.sign_count, user_verification: true)
    passkey.update!(sign_count: assertion.sign_count)
    passkey
  rescue *MALFORMED_INPUT
    nil
  end
end
