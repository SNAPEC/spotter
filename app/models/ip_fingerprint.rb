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
    OpenSSL::HMAC.hexdigest("SHA256", key, client_network(request.remote_ip))
  rescue ActionDispatch::RemoteIp::IpSpoofAttackError
    raise SpoofedHeaders, cause: nil
  end

  # One IPv6 subscriber usually holds a whole /64: keying on the full address would let a client
  # rotate through it and dodge every limit.
  def self.client_network(ip)
    address = IPAddr.new(ip.to_s)
    address = address.native if address.ipv4_mapped?
    address.ipv6? ? address.mask(64).to_s : address.to_s
  rescue IPAddr::InvalidAddressError
    ip.to_s
  end
  private_class_method :client_network

  def self.key
    @key ||= Rails.application.key_generator.generate_key("ip_fingerprint", 32)
  end
  private_class_method :key
end
