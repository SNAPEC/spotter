require "rails_helper"

RSpec.describe "Deactivated staff", type: :request do
  include ActiveJob::TestHelper

  let!(:admin) { User.create!(email: "admin1@example.test", role: "admin") }
  let!(:analyst) { User.create!(email: "analyste@example.test", role: "analyst") }

  before do
    User.create!(email: "admin2@example.test", role: "admin")
    Rails.configuration.x.rate_limit_store.clear
    ActionMailer::Base.deliveries.clear
  end

  # The CSP nonce is fresh for every response: everything else must match.
  def answer
    [ response.status, response.body.gsub(request.content_security_policy_nonce, "nonce") ]
  end

  def signed_in?
    jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
    Session.exists?(id: jar.signed[:session_id])
  end

  it "answers a magic link request exactly like for an active account, and sends nothing" do
    post login_path, params: { email: "analyste@example.test" }
    active_answer = answer

    analyst.deactivate!(by: admin)
    perform_enqueued_jobs { post login_path, params: { email: "analyste@example.test" } }

    expect(answer).to eq(active_answer)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "refuses a magic link issued before the deactivation" do
    token = analyst.magic_link_token
    analyst.deactivate!(by: admin)

    post magic_link_path(token)

    expect(response).to redirect_to(login_path)
    expect(signed_in?).to be(false)
  end

  it "drops a session cookie that was valid before the deactivation" do
    post magic_link_path(analyst.magic_link_token)
    expect(signed_in?).to be(true)
    session_row = Session.last
    analyst.deactivate!(by: admin)
    # Even if the row were still there, the cookie must not resume it.
    Session.insert_all!([ session_row.attributes ])

    get "/analyst"

    expect(response).to redirect_to(login_path)
  end

  it "refuses the passkey, recovery code and registration pages on a surviving session" do
    post magic_link_path(analyst.magic_link_token)
    analyst.deactivate!(by: admin)

    [ new_passkey_session_path, new_recovery_code_path, new_passkey_registration_path ].each do |path|
      get path
      expect(response).to redirect_to(login_path)
    end
    post recovery_code_path, params: { code: "ABCD-EFGH-IJKL" }
    expect(response).to redirect_to(login_path)
  end
end
