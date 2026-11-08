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

  MAX_BODY_BYTES = 16.kilobytes

  # The declared length is checked first, then the bytes actually read: a chunked body declares none.
  def create
    return head :content_too_large if request.content_length.to_i > MAX_BODY_BYTES

    body = request.body.read(MAX_BODY_BYTES + 1).to_s
    return head :content_too_large if body.bytesize > MAX_BODY_BYTES

    Rails.logger.warn("CSP violation: #{CspViolation.summary(body)}")
    head :no_content
  end
end
