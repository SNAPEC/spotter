require "rails_helper"

RSpec.describe "Magic link sign-in", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:ip) { "203.0.113.7" }
  let!(:user) { User.create!(email: "lea.martin@example.com") }

  before do
    ActionMailer::Base.deliveries.clear
    Rails.configuration.x.rate_limit_store.clear
  end

  def request_link(email, env: { "REMOTE_ADDR" => ip })
    perform_enqueued_jobs { post login_path, params: { email: email }, env: env }
  end

  # The CSP nonce is fresh for every response: everything else must match.
  def answer
    [ response.status, response.body.gsub(request.content_security_policy_nonce, "nonce") ]
  end

  def link_path_from_last_email
    URI(ActionMailer::Base.deliveries.last.text_part.body.decoded[%r{http://\S+/login/\S+}]).path
  end

  # The session cookie is signed; read it the way the app does.
  def signed_in_user
    jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
    Session.find_by(id: jar.signed[:session_id])&.user
  end

  it "shows the sign-in form" do
    get login_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Recevoir un lien de connexion")
  end

  it "signs a known user in through the emailed link" do
    request_link("lea.martin@example.com")
    path = link_path_from_last_email

    get path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Se connecter")

    post path
    expect(response).to redirect_to(root_path)
    expect(signed_in_user).to eq(user)
  end

  it "starts a fresh Rails session at sign-in to prevent session fixation" do
    request_link("lea.martin@example.com")
    path = link_path_from_last_email
    post "#{path}x"
    session_before = session.id.public_id

    post path

    expect(signed_in_user).to eq(user)
    expect(session.id.public_id).not_to eq(session_before)
  end

  it "does not sign in on the GET alone, so mail scanners cannot burn the link" do
    request_link("lea.martin@example.com")

    expect { get link_path_from_last_email }.not_to change(Session, :count)
  end

  it "answers an unknown email exactly like a known one and creates a declarant" do
    request_link("lea.martin@example.com")
    known = answer

    expect { request_link("nouveau@example.com") }.to change(User, :count).by(1)
    expect(answer).to eq(known)
    expect(response.body).to include("Vérifiez votre boîte")
    expect(ActionMailer::Base.deliveries.last.to).to eq([ "nouveau@example.com" ])
    expect(User.find_by(email: "nouveau@example.com")).to have_attributes(role: "declarant")
  end

  it "refuses the link after 15 minutes and 1 second" do
    request_link("lea.martin@example.com")
    path = link_path_from_last_email

    travel 15.minutes + 1.second do
      post path
    end

    expect(response).to redirect_to(login_path)
    expect(signed_in_user).to be_nil
  end

  it "refuses the link the second time" do
    request_link("lea.martin@example.com")
    path = link_path_from_last_email
    post path
    cookies.delete(:session_id)

    expect { post path }.not_to change(Session, :count)
    expect(response).to redirect_to(login_path)
  end

  it "refuses a tampered token" do
    request_link("lea.martin@example.com")

    post "#{link_path_from_last_email}x"

    expect(response).to redirect_to(login_path)
    expect(signed_in_user).to be_nil
  end

  describe "rate limiting" do
    let(:keys) { [] }

    around do |example|
      callback = ->(*, payload) { keys << payload[:key] }
      ActiveSupport::Notifications.subscribed(callback, "cache_increment.active_support") { example.run }
    end

    it "allows 5 requests in 3 minutes per client, then answers 429" do
      5.times { |n| request_link("personne#{n}@example.com") }
      expect(response).to have_http_status(:ok)

      request_link("personne5@example.com")
      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include("Trop de demandes")

      request_link("personne6@example.com", env: { "REMOTE_ADDR" => "203.0.113.8" })
      expect(response).to have_http_status(:ok)

      travel 3.minutes + 1.second do
        request_link("personne7@example.com")
        expect(response).to have_http_status(:ok)
      end
    end

    it "sends 3 links an hour per address, whatever the client, with the generic answer" do
      3.times { |n| request_link(" Lea.Martin@example.com ", env: { "REMOTE_ADDR" => "203.0.113.#{n + 10}" }) }
      expect(ActionMailer::Base.deliveries.size).to eq(3)

      request_link("lea.martin@example.com", env: { "REMOTE_ADDR" => "203.0.113.20" })
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Vérifiez votre boîte de réception")
      expect(ActionMailer::Base.deliveries.size).to eq(3)

      request_link("autre@example.com", env: { "REMOTE_ADDR" => "203.0.113.20" })
      expect(ActionMailer::Base.deliveries.size).to eq(4)

      travel 1.hour + 1.second do
        request_link("lea.martin@example.com", env: { "REMOTE_ADDR" => "203.0.113.21" })
        expect(ActionMailer::Base.deliveries.size).to eq(5)
      end
    end

    it "keys the limits on fingerprints, never on the IP or the address" do
      request_link("lea.martin@example.com")

      expect(keys.size).to eq(2)
      expect(keys.join).to include(IpFingerprint.for(ActionDispatch::Request.new("REMOTE_ADDR" => ip)))
      expect(keys.join).to include(User.email_fingerprint("lea.martin@example.com"))
      expect(keys.join).not_to include(ip)
      expect(keys.join).not_to include("lea.martin")
    end
  end

  describe "spoofed IP headers" do
    let(:io) { StringIO.new }
    let(:capture) { Logger.new(io, level: Logger::DEBUG) }

    around do |example|
      Rails.logger.broadcast_to(capture)
      example.run
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    it "answers 400 without logging either address" do
      post login_path, params: { email: "lea.martin@example.com" },
        headers: { "Client-IP" => ip, "X-Forwarded-For" => "198.51.100.4" }

      expect(response).to have_http_status(:bad_request)
      expect(io.string).to include("Started POST")
      expect(io.string).not_to include(ip)
      expect(io.string).not_to include("198.51.100.4")
    end
  end
end
