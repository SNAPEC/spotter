require "rails_helper"
require "kamal"

# Read through Kamal itself, without connecting anywhere: what the proxy, the app and the database run with.
RSpec.describe "Kamal deploy configuration" do
  subject(:config) do
    Kamal::Configuration.create_from(config_file: Rails.root.join("config/deploy.yml"), version: "test")
  end

  let(:server) { "spotter-server.test" }
  let(:proxy_run) { Kamal::Commands::Proxy.new(config, host: server).run.join(" ") }
  let(:database) { config.accessory(:db) }

  around do |example|
    previous = ENV["SPOTTER_SERVER_IP"]
    ENV["SPOTTER_SERVER_IP"] = server
    example.run
  ensure
    ENV["SPOTTER_SERVER_IP"] = previous
  end

  it "reads the server address from the environment, the repository being public" do
    expect(config.all_hosts).to eq([ server ])
    expect(database.hosts).to eq([ server ])
    expect(Rails.root.join("config/deploy.yml").read).not_to match(/\d+\.\d+\.\d+\.\d+/)
  end

  it "serves the domain over TLS and checks the health on /up" do
    proxy = config.role(:web).proxy

    expect(proxy.hosts).to eq([ "spotter.rosalp.fr" ])
    expect(proxy).to be_ssl
    expect(proxy.deploy_options).to include("health-check-path": "/up")
  end

  it "keeps no kamal-proxy log, since its request lines carry the client IP" do
    expect(proxy_run).to include('--log-driver "none"', "basecamp/kamal-proxy:v0.10.3")
    expect(proxy_run).not_to include("--log-opt")
  end

  it "turns off Thruster request logs" do
    expect(config.env.clear).to include("THRUSTER_LOG_REQUESTS" => false)
  end

  it "pushes images through the local registry" do
    expect(config.registry).to be_local
  end

  it "keeps the database off any public port, its data in a volume" do
    expect(database.publish_args).to be_nil
    expect(database.volume_args).to include("spotter_db_data:/var/lib/postgresql/data")
  end

  it "keeps request data and ciphertexts out of the database logs" do
    expect(database.cmd).to include(
      "log_error_verbosity=terse", "log_connections=off", "log_disconnections=off", "log_statement=none",
      "log_min_error_statement=panic", "track_commit_timestamp=off"
    )
    expect(database.cmd[/log_line_prefix='([^']*)'/, 1]).not_to match(/%[hr]/)
  end
end
