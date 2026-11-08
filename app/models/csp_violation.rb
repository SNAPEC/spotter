# A browser's CSP violation report, cut down to what helps fix the policy: the directive and the
# blocked origin. The document URL (ids) and anything about the client are dropped.
class CspViolation
  MAX_BYTES = 8.kilobytes
  KEYWORDS = %w[inline eval wasm-eval self data blob trusted-types-policy trusted-types-sink].freeze

  def self.summary(raw_report)
    report = parse(raw_report)
    "directive=#{directive(report)} blocked=#{blocked(report["blocked-uri"])}"
  end

  def self.parse(raw_report)
    report = JSON.parse(raw_report.to_s.byteslice(0, MAX_BYTES))
    report.is_a?(Hash) && report["csp-report"].is_a?(Hash) ? report["csp-report"] : {}
  rescue JSON::ParserError
    {}
  end

  def self.directive(report)
    (report["effective-directive"] || report["violated-directive"]).to_s[/\A[a-z-]{1,40}/] || "unknown"
  end

  def self.blocked(uri)
    uri = uri.to_s
    return uri if KEYWORDS.include?(uri)

    parsed = URI.parse(uri)
    host = parsed.host.to_s.delete_prefix("[").delete_suffix("]")
    return parsed.scheme.to_s[/\A[a-z][a-z0-9+.-]{0,19}\z/] || "unknown" if host.empty?
    return "#{parsed.scheme}://ip-address" if ip_address?(host)

    "#{parsed.scheme}://#{host[/\A[a-z0-9.-]{1,253}\z/i] || "unknown"}"
  rescue URI::Error
    "unknown"
  end

  def self.ip_address?(host)
    IPAddr.new(host)
    true
  rescue IPAddr::InvalidAddressError
    false
  end
  private_class_method :parse, :directive, :blocked, :ip_address?
end
