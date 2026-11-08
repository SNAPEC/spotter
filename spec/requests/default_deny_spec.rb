require "rails_helper"

# Default deny: a new controller must say which roles it serves, or be listed here with the reason.
# The check is per controller: a `require_role ..., only:` covering some actions passes it for all of
# them, so a partial `only:` (or `except:`) needs a reviewer's eye on the remaining actions.
RSpec.describe "Every controller" do
  let(:exemptions) do
    {
      "MagicLinksController" => "sign-in, before any role is known",
      "SessionsController" => "signing out, open to every signed-in role",
      "CspReportsController" => "browser violation reports, sent outside any session",
      "Dev::LoginsController" => "development only, refused elsewhere",
      "Dev::StyleguideController" => "development only, refused elsewhere"
    }
  end

  let(:controllers) do
    Rails.root.glob("app/controllers/**/*_controller.rb").map do |path|
      path.relative_path_from(Rails.root.join("app/controllers")).to_s.delete_suffix(".rb").camelize.constantize
    end - [ ApplicationController ]
  end

  def requires_role?(controller)
    controller._process_action_callbacks.any? do |callback|
      callback.kind == :before && callback.filter.is_a?(Proc) &&
        callback.filter.source_location.first.end_with?("app/controllers/concerns/authorization.rb")
    end
  end

  it "declares require_role or is an explicit exemption" do
    undeclared = controllers.reject { |controller| requires_role?(controller) }.map(&:name)

    expect(undeclared - exemptions.keys).to be_empty
  end

  it "keeps the exemption list free of stale entries" do
    exempted = controllers.select { |controller| exemptions.key?(controller.name) }

    expect(exempted.map(&:name)).to match_array(exemptions.keys)
    expect(exempted.select { |controller| requires_role?(controller) }).to be_empty
  end

  it "detects require_role where it is declared" do
    expect(requires_role?(Admin::HomeController)).to be(true)
    expect(requires_role?(MagicLinksController)).to be(false)
  end
end
