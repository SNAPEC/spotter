class Passkey < ApplicationRecord
  class InvalidCredential < StandardError; end

  REQUIRED_RESPONSE_FIELDS = {
    create: %w[clientDataJSON attestationObject],
    get: %w[clientDataJSON authenticatorData signature]
  }.freeze
  BASE64URL = /\A[A-Za-z0-9_-]+={0,2}\z/

  belongs_to :user

  validates :external_id, :public_key, presence: true

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

  # JSON::ParserError too: the gem parses the decoded clientDataJSON itself.
  # The unique index on external_id, not a validation, settles two concurrent submits of one credential.
  def self.register!(user:, credential:, challenge:, nickname: nil)
    attestation = WebAuthn::Credential.from_create(parse(credential, :create))
    attestation.verify(challenge, user_verification: true)

    user.passkeys.create!(
      external_id: attestation.id,
      public_key: attestation.public_key,
      sign_count: attestation.sign_count,
      nickname: nickname.presence
    )
  rescue WebAuthn::Error, JSON::ParserError, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
    raise InvalidCredential, error.class.name
  end

  def self.authenticate(user:, credential:, challenge:)
    assertion = WebAuthn::Credential.from_get(parse(credential, :get))
    passkey = user.passkeys.find_by(external_id: assertion.id)
    return unless passkey

    assertion.verify(challenge, public_key: passkey.public_key, sign_count: passkey.sign_count, user_verification: true)
    passkey.update!(sign_count: assertion.sign_count)
    passkey
  rescue WebAuthn::Error, JSON::ParserError, InvalidCredential
    nil
  end

  # Checks the shape the browser must send, so that junk is refused before the WebAuthn library touches it.
  def self.parse(credential, ceremony)
    json = JSON.parse(credential.to_s)
    response = json["response"] if json.is_a?(Hash)

    valid = response.is_a?(Hash) && json["type"] == "public-key" &&
      [ json["id"], json["rawId"], *response.values_at(*REQUIRED_RESPONSE_FIELDS.fetch(ceremony)) ].all? { |value| value.is_a?(String) && value.match?(BASE64URL) }
    raise InvalidCredential, "malformed credential" unless valid

    json
  rescue JSON::ParserError
    raise InvalidCredential, "malformed credential"
  end
  private_class_method :parse
end
