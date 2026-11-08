require "rails_helper"

# A new route is closed by default: a signed-out request must be sent to the sign-in page, or, for a
# development-only route, find nothing. Any other answer, or a route this spec cannot request, needs an
# entry below with its reason.
RSpec.describe "Routes for a signed-out visitor", type: :request do
  OPEN_ROUTES = {
    "GET /login" => "sign-in form",
    "POST /login" => "asks for a magic link",
    "GET /login/:token" => "magic link confirmation",
    "POST /login/:token" => "magic link consumption",
    "GET /up" => "health check, no data",
    "GET /recede_historical_location" => "Turbo Native history helper: a static page, no data",
    "GET /resume_historical_location" => "Turbo Native history helper: a static page, no data",
    "GET /refresh_historical_location" => "Turbo Native history helper: a static page, no data",
    "POST /rails/action_mailbox/postmark/inbound_emails" => "Action Mailbox ingress: 404 while no ingress is configured",
    "POST /rails/action_mailbox/relay/inbound_emails" => "Action Mailbox ingress: 404 while no ingress is configured",
    "POST /rails/action_mailbox/sendgrid/inbound_emails" => "Action Mailbox ingress: 404 while no ingress is configured",
    "GET /rails/action_mailbox/mandrill/inbound_emails" => "Action Mailbox ingress: 404 while no ingress is configured",
    "POST /rails/action_mailbox/mandrill/inbound_emails" => "Action Mailbox ingress: 404 while no ingress is configured",
    "POST /rails/action_mailbox/mailgun/inbound_emails/mime" => "Action Mailbox ingress: 404 while no ingress is configured",
    "GET /rails/conductor/action_mailbox/inbound_emails" => "Action Mailbox conductor: refused outside development",
    "POST /rails/conductor/action_mailbox/inbound_emails" => "Action Mailbox conductor: refused outside development",
    "GET /rails/conductor/action_mailbox/inbound_emails/new" => "Action Mailbox conductor: refused outside development",
    "GET /rails/conductor/action_mailbox/inbound_emails/:id" => "Action Mailbox conductor: refused outside development",
    "GET /rails/conductor/action_mailbox/inbound_emails/sources/new" => "Action Mailbox conductor: refused outside development",
    "POST /rails/conductor/action_mailbox/inbound_emails/sources" => "Action Mailbox conductor: refused outside development",
    "POST /rails/conductor/action_mailbox/:inbound_email_id/reroute" => "Action Mailbox conductor: refused outside development",
    "POST /rails/conductor/action_mailbox/:inbound_email_id/incinerate" => "Action Mailbox conductor: refused outside development"
  }.freeze

  def self.routes
    Rails.application.routes.routes.map do |route|
      verb = route.verb.presence || "MOUNT"
      "#{verb} #{route.path.spec.to_s.delete_suffix("(.:format)")}"
    end.uniq
  end

  it "can request every route that is not listed as open" do
    expect(self.class.routes.select { |key| key.start_with?("MOUNT ") } - OPEN_ROUTES.keys).to be_empty
  end

  it "lists only routes that exist" do
    expect(OPEN_ROUTES.keys - self.class.routes).to be_empty
  end

  (routes - OPEN_ROUTES.keys).reject { |key| key.start_with?("MOUNT ") }.each do |key|
    verb, path = key.split(" ", 2)

    it "closes #{key}" do
      process verb.downcase.to_sym, path.gsub(/[:*]\w+/, "1")

      if path.start_with?("/dev/")
        expect(response).to have_http_status(:not_found)
      else
        expect(response).to redirect_to(login_url)
      end
    end
  end
end
