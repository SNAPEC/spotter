require "rails_helper"
require "open3"

# The production environment is booted in its own process: its settings can only be read from there.
RSpec.describe "Production configuration" do
  probe = <<~RUBY
    # kamal-proxy forwards plain HTTP with the original Host header.
    request = lambda do |host, path|
      status, headers = Rails.application.call(Rack::MockRequest.env_for("http://\#{host}\#{path}", "HTTP_HOST" => host))
      [ status, headers["location"], headers["strict-transport-security"].present? ]
    end
    config = Rails.configuration
    puts JSON.generate(
      hosts: config.hosts.map(&:to_s),
      assume_ssl: config.assume_ssl,
      force_ssl: config.force_ssl,
      session: config.session_options.slice(:secure, :same_site),
      webauthn: [ WebAuthn.configuration.allowed_origins, WebAuthn.configuration.rp_id ],
      url_options: config.action_mailer.default_url_options,
      delivery_method: config.action_mailer.delivery_method,
      smtp: config.action_mailer.smtp_settings.slice(:address, :port, :enable_starttls),
      from: ApplicationMailer.default[:from],
      on_domain: request.("spotter.rosalp.fr", "/up"),
      foreign_host: request.("other.example", "/login"),
      health_check: request.("spotter-web", "/up")
    )
  RUBY

  # Booted once: a boot takes seconds.
  before(:context) do
    env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1", "RAILS_MASTER_KEY" => nil, "DATABASE_URL" => nil }
    output, status = Open3.capture2(env, "bin/rails", "runner", probe, chdir: Rails.root.to_s, err: File::NULL)
    raise "production boot failed" unless status.success?
    # A gem may print a warning before the probe's line.
    @production = JSON.parse(output.lines.last, symbolize_names: true)
  end

  attr_reader :production

  it "serves the app over HTTPS on its domain only, the health check from any host" do
    expect(production).to include(
      hosts: [ "spotter.rosalp.fr" ], assume_ssl: true, force_ssl: true,
      session: { secure: true, same_site: "lax" },
      on_domain: [ 200, nil, true ],
      foreign_host: [ 403, nil, false ],
      health_check: [ 200, nil, true ]
    )
  end

  it "binds passkeys and mail links to the domain" do
    expect(production).to include(
      webauthn: [ [ "https://spotter.rosalp.fr" ], "spotter.rosalp.fr" ],
      url_options: { host: "spotter.rosalp.fr", protocol: "https" },
      from: "Spotter <ne-pas-repondre@spotter.rosalp.fr>"
    )
  end

  it "sends mail through Scaleway Transactional Email over STARTTLS" do
    expect(production).to include(
      delivery_method: "smtp",
      smtp: { address: "smtp.tem.scaleway.com", port: 2587, enable_starttls: true }
    )
  end
end
