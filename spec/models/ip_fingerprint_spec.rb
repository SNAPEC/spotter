require "rails_helper"

RSpec.describe IpFingerprint do
  def request_from(ip)
    ActionDispatch::Request.new("REMOTE_ADDR" => ip)
  end

  it "returns a keyed SHA-256 digest that does not contain the IP" do
    fingerprint = IpFingerprint.for(request_from("203.0.113.7"))

    expect(fingerprint).to match(/\A\h{64}\z/)
    expect(fingerprint).not_to include("203.0.113.7")
  end

  it "is stable for one IP and differs between IPs" do
    expect(IpFingerprint.for(request_from("203.0.113.7"))).to eq(IpFingerprint.for(request_from("203.0.113.7")))
    expect(IpFingerprint.for(request_from("203.0.113.7"))).not_to eq(IpFingerprint.for(request_from("203.0.113.8")))
  end

  it "treats every address of one IPv6 /64 as one client" do
    expect(IpFingerprint.for(request_from("2001:db8:1:2::7"))).to eq(IpFingerprint.for(request_from("2001:db8:1:2:abcd::1")))
    expect(IpFingerprint.for(request_from("2001:db8:1:2::7"))).not_to eq(IpFingerprint.for(request_from("2001:db8:1:3::7")))
  end

  it "treats an IPv4-mapped IPv6 address as its IPv4 address" do
    expect(IpFingerprint.for(request_from("::ffff:203.0.113.7"))).to eq(IpFingerprint.for(request_from("203.0.113.7")))
  end

  it "is not a bare SHA-256 of the IP" do
    expect(IpFingerprint.for(request_from("203.0.113.7"))).not_to eq(Digest::SHA256.hexdigest("203.0.113.7"))
  end

  it "refuses conflicting IP headers without carrying the addresses" do
    env = { "REMOTE_ADDR" => "127.0.0.1", "HTTP_CLIENT_IP" => "203.0.113.7", "HTTP_X_FORWARDED_FOR" => "198.51.100.4" }
    env["action_dispatch.remote_ip"] = ActionDispatch::RemoteIp::GetIp.new(ActionDispatch::Request.new(env), true, [])

    expect { IpFingerprint.for(ActionDispatch::Request.new(env)) }.to raise_error(IpFingerprint::SpoofedHeaders) { |error|
      expect(error.message).not_to include("203.0.113.7")
      expect(error.cause).to be_nil
    }
  end
end
