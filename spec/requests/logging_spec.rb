require "rails_helper"

RSpec.describe "Request logging", type: :request do
  let(:ip) { "203.0.113.7" }
  let(:io) { StringIO.new }

  around do |example|
    original = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(io, level: Logger::INFO))
    example.run
  ensure
    Rails.logger = original
  end

  it "logs the request line without the client IP address" do
    get "/up", env: { "REMOTE_ADDR" => ip }

    expect(io.string).to include("Started GET")
    expect(io.string).not_to include(ip)
  end

  it "keeps the IP out of the log even behind a forwarding header" do
    get "/up", headers: { "X-Forwarded-For" => ip }

    expect(io.string).to include("Started GET")
    expect(io.string).not_to include(ip)
  end

  it "masks the magic link token on both the GET and the POST" do
    token = User.create!(email: "lea.martin@example.com").magic_link_token

    get "/login/#{token}"
    post "/login/#{token}"

    expect(io.string.scan('Started GET "/login/[FILTERED]"').size).to eq(1)
    expect(io.string.scan('Started POST "/login/[FILTERED]"').size).to eq(1)
    expect(io.string).not_to include(token)
  end
end
