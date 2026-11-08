require "rails_helper"

# A new route is closed by default: a signed-out request must be sent to the sign-in page or find nothing,
# unless the route is listed here on purpose.
RSpec.describe "Routes for a signed-out visitor", type: :request do
  OPEN_ROUTES = {
    "GET /login" => "sign-in form",
    "POST /login" => "asks for a magic link",
    "GET /login/:token" => "magic link confirmation",
    "POST /login/:token" => "magic link consumption",
    "GET /up" => "health check"
  }.freeze

  # Mounted by Rails engines: Turbo Native history helpers, Action Mailbox ingresses (inactive) and Active
  # Storage, whose URLs are signed.
  FRAMEWORK_PREFIXES = %w[/rails/ /recede_historical_location /resume_historical_location /refresh_historical_location].freeze

  def self.app_routes
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.delete_suffix("(.:format)")
      next if path.start_with?(*FRAMEWORK_PREFIXES) || route.verb.blank?

      [ route.verb, path ]
    end.uniq
  end

  it "covers the application's own routes" do
    expect(self.class.app_routes).to include([ "GET", "/" ], [ "GET", "/admin" ], [ "GET", "/dev/login" ])
  end

  app_routes.each do |verb, path|
    key = "#{verb} #{path}"
    next if OPEN_ROUTES.key?(key)

    it "closes #{key}" do
      process verb.downcase.to_sym, path.gsub(/[:*]\w+/, "1")

      outcome = response.not_found? ? :not_found : response.location
      expect(outcome).to eq(:not_found).or eq(login_url)
    end
  end
end
