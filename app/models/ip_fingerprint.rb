# Rate limiting needs a per-client key, but the IP itself must never be stored.
module IpFingerprint
  # Rails' own spoofing error carries both addresses in its message, and
  # rescue_from logs that message: re-raise without it and without a cause.
  class SpoofedHeaders < StandardError
    def initialize(message = "Conflicting client IP headers")
      super
    end
  end

  def self.for(request)
    OpenSSL::HMAC.hexdigest("SHA256", key, request.remote_ip)
  rescue ActionDispatch::RemoteIp::IpSpoofAttackError
    raise SpoofedHeaders, cause: nil
  end

  def self.key
    @key ||= Rails.application.key_generator.generate_key("ip_fingerprint", 32)
  end
  private_class_method :key
end
