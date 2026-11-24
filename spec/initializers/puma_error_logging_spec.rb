require "rails_helper"

RSpec.describe "Puma error logging" do
  let(:stderr) { StringIO.new }
  let(:log_writer) { Puma::LogWriter.new(StringIO.new, stderr, env: { "PUMA_DEBUG" => "1" }) }
  let(:error) { RuntimeError.new("invalid byte in /login/secret-token from 203.0.113.7") }
  let(:request) do
    Struct.new(:env, :body).new({
      "REQUEST_METHOD" => "GET",
      "REQUEST_PATH" => "/login/secret-token",
      "QUERY_STRING" => "email=someone%40example.org",
      "REMOTE_ADDR" => "203.0.113.7",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.23",
      "HTTP_COOKIE" => "_spotter_session=secret"
    }, "")
  end

  def expect_nothing_from_the_request
    expect(stderr.string).not_to include("203.0.113.7", "198.51.100.23", "secret", "email", "/login")
  end

  it "writes a parse error without the request" do
    log_writer.parse_error(error, request)

    expect(stderr.string).to include("HTTP parse error, malformed request: RuntimeError")
    expect_nothing_from_the_request
  end

  it "writes an application error without the request nor the exception message" do
    log_writer.unknown_error(error, request, "Rack app")

    expect(stderr.string).to include("Rack app: RuntimeError")
    expect_nothing_from_the_request
  end

  it "writes a connection error without the request" do
    log_writer.connection_error(error, request)

    expect(stderr.string).to include("HTTP connection error: RuntimeError")
    expect_nothing_from_the_request
  end

  it "dumps no request in debug mode" do
    log_writer.debug_error(error, request)

    expect(stderr.string).to include("RuntimeError")
    expect_nothing_from_the_request
  end

  it "writes an SSL error without the peer address" do
    socket = Struct.new(:peeraddr, :peercert).new([ "AF_INET", 443, "203.0.113.7", "203.0.113.7" ], nil)

    log_writer.ssl_error(error, socket)

    expect(stderr.string).to include("SSL error: RuntimeError")
    expect_nothing_from_the_request
  end
end
