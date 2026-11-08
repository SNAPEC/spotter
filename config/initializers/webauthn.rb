WebAuthn.configure do |config|
  config.allowed_origins = [ Rails.configuration.x.webauthn.origin ]
  config.rp_id = Rails.configuration.x.webauthn.rp_id
  config.rp_name = "Spotter"
end
