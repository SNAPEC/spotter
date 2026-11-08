require "rails_helper"

RSpec.describe "Request logging", type: :request do
  let(:ip) { "203.0.113.7" }
  let(:io) { StringIO.new }

  # Masked as the initializer masks every logger behind Rails.logger.
  around do |example|
    logger = NoIpLogging.install(ActiveSupport::Logger.new(io, level: :info))
    Rails.logger.broadcast_to(logger)
    example.run
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  it "masks through every logger behind Rails.logger, keeping the request id tag" do
    logger = NoIpLogging.install(ActiveSupport::TaggedLogging.logger(io))
    id = SecureRandom.uuid

    logger.tagged(id) { logger.info("Report #{id}") }

    expect(Rails.logger.broadcasts).to all(satisfy { |each| each.formatter.is_a?(Logstop::Formatter) })
    expect(io.string).to eq("[#{id}] Report [FILTERED]\n")
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

  it "masks the magic link token in a routing error too" do
    token = User.create!(email: "lea.martin@example.com").magic_link_token

    get "/login/#{token}/extra"

    expect(io.string).to include('No route matches [GET] "/login/[FILTERED]/extra"')
    expect(io.string).not_to include(token)
  end

  it "masks an exception passed to the logger as is" do
    id = SecureRandom.uuid

    Rails.logger.error(ArgumentError.new("Couldn't process Report #{id} for lea.martin@example.com"))

    expect(io.string).to include("ArgumentError", "Couldn't process Report [FILTERED] for [FILTERED]")
    expect(io.string).not_to include(id)
  end

  it "masks any id in the request line, including on a 404" do
    id = SecureRandom.uuid

    post "/reports/#{id}/clarifications"

    expect(io.string).to include('Started POST "/reports/[FILTERED]/clarifications"')
    expect(io.string).to include('No route matches [POST] "/reports/[FILTERED]/clarifications"')
    expect(io.string).not_to include(id)
  end

  it "masks an id in the query string, whatever the parameter" do
    id = SecureRandom.uuid

    get "/login?report=#{id}&next=/reports/#{id}/edit"

    expect(io.string).to include('"report" => "[FILTERED]"')
    expect(io.string).not_to include(id)
  end

  it "logs a redirect to a location holding an id without the id" do
    id = SecureRandom.uuid

    ActiveSupport::Notifications.instrument("redirect_to.action_controller", location: "http://www.example.com/reports/#{id}")

    expect(io.string).to include("Redirected to http://www.example.com/reports/[FILTERED]")
    expect(io.string).not_to include(id)
  end

  it "logs an unrescued exception without the id its message quotes" do
    id = SecureRandom.uuid
    app = ActionDispatch::DebugExceptions.new(->(_env) { raise ArgumentError, "Couldn't process Report #{id}" })
    env = Rack::MockRequest.env_for("/", "action_dispatch.show_exceptions" => :all,
      "action_dispatch.show_detailed_exceptions" => false, "action_dispatch.logger" => Rails.logger)

    expect { app.call(env) }.to raise_error(ArgumentError)

    expect(io.string).to include("ArgumentError (Couldn't process Report [FILTERED])")
    expect(io.string).not_to include(id)
  end

  it "logs no blob key when storing a file" do
    service, key = ActiveStorage::Blob.service, ActiveStorage::Blob.generate_unique_secure_token

    service.upload(key, StringIO.new("Fichier fictif"))
    service.delete(key)

    expect(io.string).not_to include(key)
  end
end
