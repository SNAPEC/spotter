require "rails_helper"

RSpec.describe "Request logging", type: :request do
  let(:ip) { "203.0.113.7" }
  let(:io) { StringIO.new }

  around do |example|
    original, original_controller = Rails.logger, ActionController::Base.logger
    Rails.logger = ActionController::Base.logger = ActiveSupport::TaggedLogging.new(Logger.new(io, level: Logger::INFO))
    example.run
  ensure
    Rails.logger, ActionController::Base.logger = original, original_controller
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

  it "masks any id in the request line, including on a 404" do
    id = SecureRandom.uuid

    post "/reports/#{id}/clarifications", env: { "action_dispatch.logger" => Rails.logger }

    expect(io.string).to include('Started POST "/reports/[FILTERED]/clarifications"')
    expect(io.string).not_to include(id)
  end

  it "masks an id in the query string, whatever the parameter" do
    id = SecureRandom.uuid

    get "/login?report=#{id}&next=/reports/#{id}/edit"

    expect(io.string).to include('"report" => "[FILTERED]"')
    expect(io.string).not_to include(id)
  end

  it "logs a redirect to a location holding an id as filtered" do
    request = ActionDispatch::Request.new(Rails.application.env_config.dup)
    response = ActionDispatch::Response.new
    response.request = request
    response.location = "http://www.example.com/reports/#{SecureRandom.uuid}"

    expect(response.filtered_location).to eq("[FILTERED]")
  end
end
