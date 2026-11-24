require "rails_helper"

# The repository and its Actions logs are public: the deploy job holds the production secrets.
RSpec.describe "Deploy job of the CI workflow" do
  let(:workflow_file) { Rails.root.join(".github/workflows/ci.yml") }
  let(:workflow) { YAML.load_file(workflow_file) }
  # Psych reads the bare `on` key as true.
  let(:triggers) { workflow.fetch(true) }
  let(:deploy) { workflow.dig("jobs", "deploy") }
  let(:scripts) { deploy["steps"].filter_map { |step| step["run"] }.join("\n") }

  it "runs on a push to main only, never for a pull request target" do
    expect(triggers.keys).to contain_exactly("pull_request", "push")
    expect(triggers.dig("push", "branches")).to eq([ "main" ])
    expect(deploy["if"]).to eq("github.event_name == 'push' && github.ref == 'refs/heads/main'")
  end

  it "waits for every other CI job" do
    expect(deploy["needs"]).to match_array(workflow["jobs"].keys - [ "deploy" ])
  end

  it "goes through the production environment, one deploy at a time" do
    expect(deploy.dig("environment", "name")).to eq("production")
    expect(deploy["concurrency"]).to include("cancel-in-progress" => false)
    expect(deploy["permissions"]).to eq("contents" => "read")
  end

  it "uses actions pinned by commit" do
    uses = deploy["steps"].filter_map { |step| step["uses"] }

    expect(uses).to all(match(/@\h{40}\z/))
  end

  it "masks the server address and checks the server host key" do
    expect(scripts).to include("::add-mask::${SPOTTER_SERVER_IP}")
    expect(scripts).to include("StrictHostKeyChecking yes")
    expect(scripts).not_to match(/StrictHostKeyChecking[ =]no/)
  end

  it "runs kamal without its verbose output, which prints each command's environment" do
    expect(scripts).to include("bin/kamal deploy")
    expect(scripts).not_to match(/kamal .*(-v\b|--verbose)/)
  end

  it "gives each secret only to the step that needs it, and leaves no credential behind" do
    expect(deploy).not_to have_key("env")
    checkout = deploy["steps"].find { |step| step["uses"]&.start_with?("actions/checkout@") }
    expect(checkout.dig("with", "persist-credentials")).to be(false)
    cleanup = deploy["steps"].last
    expect(cleanup["if"]).to eq("always()")
    expect(cleanup["run"]).to include("rm -f config/master.key")
  end

  it "has no workflow that runs with secrets on behalf of a pull request" do
    Rails.root.glob(".github/workflows/*.yml").each do |file|
      expect(YAML.load_file(file).fetch(true).keys).not_to include("pull_request_target", "workflow_run"), file.to_s
    end
  end
end
