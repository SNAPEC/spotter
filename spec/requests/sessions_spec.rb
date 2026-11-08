require "rails_helper"

RSpec.describe "Sessions", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "lea.martin@example.com") }

  def sign_in(user)
    post magic_link_path(user.magic_link_token)
  end

  def session_cookie_header
    Array(response.headers["Set-Cookie"]).join("\n").lines.find { |line| line.start_with?("session_id=") }
  end

  it "sets a session cookie that expires with the session, not in 20 years" do
    travel_to Time.zone.local(2026, 11, 17, 10) do
      sign_in(user)
    end

    expect(user.sessions.sole.expires_on).to eq(Date.new(2026, 12, 31))
    expect(session_cookie_header).to include("expires=Thu, 31 Dec 2026 23:59:59 GMT")
  end

  it "drops the cookie once the session has expired" do
    travel_to Date.new(2026, 11, 17) do
      sign_in(user)
    end

    travel_to Date.new(2027, 1, 1) do
      delete session_path
    end

    expect(response).to redirect_to(login_path)
    expect(flash[:notice]).to be_nil
    expect(user.sessions.count).to eq(1)
  end

  it "treats an expired session as signed out, clears its cookie and keeps the row for the purge job" do
    sign_in(user)
    user.sessions.sole.update!(expires_on: Date.yesterday)

    expect { delete sessions_path }.not_to change { user.reload.login_token_version }
    expect(response).to redirect_to(login_path)
    expect(flash[:notice]).to be_nil
    expect(session_cookie_header).to include("expires=Thu, 01 Jan 1970")
    expect(user.sessions.count).to eq(1)
  end

  it "does not write on a GET that sees an expired session" do
    sign_in(user)
    user.sessions.sole.update!(expires_on: Date.yesterday)

    get root_path

    expect(response.body).not_to include("Se déconnecter")
    expect(session_cookie_header).to include("expires=Thu, 01 Jan 1970")
    expect(user.sessions.count).to eq(1)
  end

  it "signs out of the current session only" do
    other = user.sessions.create!
    sign_in(user)

    expect { delete session_path }.to change(Session, :count).by(-1)
    expect(response).to redirect_to(login_path)
    expect(Session.exists?(other.id)).to be(true)

    follow_redirect!
    expect(response.body.scan(I18n.t("sessions.signed_out")).size).to eq(1)
    expect(response.body).to include('<html lang="fr">')
  end

  it "signs out everywhere and kills a pending magic link" do
    user.sessions.create!
    sign_in(user)
    pending_token = user.reload.magic_link_token

    delete sessions_path

    expect(response).to redirect_to(login_path)
    expect(user.sessions.reload).to be_empty
    post magic_link_path(pending_token)
    expect(response).to redirect_to(login_path)
    expect(user.sessions.reload).to be_empty
  end

  it "offers both sign-out buttons once signed in" do
    get root_path
    expect(response.body).not_to include("Se déconnecter")

    sign_in(user)
    get root_path

    expect(response.body).to include("Se déconnecter", "Se déconnecter partout")
  end

  it "requires a session to sign out" do
    delete session_path

    expect(response).to redirect_to(login_path)
  end
end
