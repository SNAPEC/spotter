# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :raw_text, :debrief, :body, :tracking_code, :code, :credential, :digest, :answers, :anonymized,
  # Any id, whatever its key: see config/initializers/no_ip_logging.rb. The filter hands over a copy.
  ->(_key, value) { value.gsub!(NoIpLogging::UUID, NoIpLogging::FILTERED) if value.is_a?(String) }
]
