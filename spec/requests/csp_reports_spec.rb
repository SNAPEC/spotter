require "rails_helper"

RSpec.describe "CSP violation reports", type: :request do
  let(:ip) { "203.0.113.7" }
  let(:io) { StringIO.new }
  let(:report_id) { SecureRandom.uuid }

  around do |example|
    logger = NoIpLogging.install(ActiveSupport::Logger.new(io, level: :info))
    Rails.logger.broadcast_to(logger)
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
    Rails.logger.stop_broadcasting_to(logger)
  end

  before { Rails.configuration.x.rate_limit_store.clear }

  def report(blocked_uri, directive: "script-src-elem")
    { "csp-report" => {
      "document-uri" => "https://spotter.example/analyst/reports/#{report_id}?token=fictif",
      "referrer" => "https://spotter.example/reports/#{report_id}",
      "violated-directive" => directive, "effective-directive" => directive,
      "blocked-uri" => blocked_uri, "script-sample" => "alert('fictif')"
    } }.to_json
  end

  def send_report(body, content_type: "application/csp-report")
    post "/csp_reports", params: body, headers: { "CONTENT_TYPE" => content_type }, env: { "REMOTE_ADDR" => ip }
  end

  it "is declared in the policy" do
    get login_path

    expect(response.headers["Content-Security-Policy"]).to include("report-uri /csp_reports")
  end

  it "accepts a report without a session or CSRF token and logs only the directive and the blocked origin" do
    send_report(report("https://cdn.example.net/lib/#{report_id}.js?k=v"))

    expect(response).to have_http_status(:no_content)
    expect(io.string).to include("CSP violation: directive=script-src-elem blocked=https://cdn.example.net")
    expect(io.string).not_to include(report_id, "fictif", "/lib/", ip)
  end

  it "logs keywords as they are and hides an IP address in the blocked origin" do
    send_report(report("inline"))
    send_report(report("http://198.51.100.4/x.js"))
    send_report(report("data:image/png;base64,AAAA", directive: "img-src"))

    expect(io.string).to include("blocked=inline", "blocked=http://ip-address", "directive=img-src blocked=data")
    expect(io.string).not_to include("198.51.100.4", "AAAA")
  end

  it "keeps the report out of the parameters log line when sent as JSON" do
    send_report(report("inline"), content_type: "application/json")

    expect(response).to have_http_status(:no_content)
    expect(io.string).not_to include(report_id, "fictif")
  end

  it "shrugs off garbage" do
    send_report("not json")
    send_report("[1]")

    expect(response).to have_http_status(:no_content)
    expect(io.string.scan("directive=unknown blocked=unknown").size).to eq(2)
  end

  it "is rate limited per client" do
    20.times { send_report(report("inline")) }
    expect(response).to have_http_status(:no_content)

    send_report(report("inline"))
    expect(response).to have_http_status(:too_many_requests)
  end

  it "is the only controller exempt from CSRF protection" do
    Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/controllers"))
    exempt = ApplicationController.descendants.reject do |controller|
      controller._process_action_callbacks.any? { |callback| callback.filter == :verify_authenticity_token }
    end

    expect(exempt).to eq([ CspReportsController ])
  end
end
