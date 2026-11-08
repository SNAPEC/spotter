# Browsers post CSP violation reports here, outside any session and without a CSRF token: the
# endpoint changes nothing and writes one scrubbed log line.
class CspReportsController < ApplicationController
  allow_unauthenticated_access
  allow_pending_passkey
  allow_recovered_session
  skip_forgery_protection
  rate_limit to: 20, within: 1.minute,
    by: -> { IpFingerprint.for(request) },
    with: -> { head :too_many_requests },
    store: Rails.configuration.x.rate_limit_store || cache_store

  def create
    Rails.logger.warn("CSP violation: #{CspViolation.summary(request.raw_post)}")
    head :no_content
  end
end
