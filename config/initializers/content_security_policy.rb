# Be sure to restart your server when you modify this file.

# See the Securing Rails Applications Guide:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.object_src :none
    policy.img_src :self, :data
    policy.script_src :self
    policy.style_src :self
  end

  # The importmap and Turbo's progress bar are inline: they carry this nonce instead of 'unsafe-inline'.
  # Fresh per response: a visitor without a Rails session yet would otherwise get an empty nonce.
  # Turbo ignores nonces when it compares heads, so its visits keep the first page's importmap; this is
  # also why the app keeps no inline script in a body.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
  config.content_security_policy_nonce_auto = true
end
