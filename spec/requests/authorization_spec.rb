require "rails_helper"

RSpec.describe "Authorization", type: :request do
  def sign_in(user)
    post magic_link_path(user.magic_link_token)
    post recovery_code_path, params: { code: user.generate_recovery_codes!.first } if user.staff?
  end

  def user_with(role)
    User.create!(email: "#{role}@example.com", role: role)
  end

  it "redirects a signed-out visitor to the sign-in page" do
    %w[/ /analyst /admin].each do |path|
      get path
      expect(response).to redirect_to(login_path)
    end
  end

  it "sends a visitor back to the protected page after sign-in" do
    get "/analyst"
    expect(response).to redirect_to(login_path)

    post magic_link_path(user_with("analyst").magic_link_token)

    expect(response).to redirect_to("http://www.example.com/analyst")
  end

  it "lets a declarant in the declarant home only" do
    sign_in(user_with("declarant"))

    get "/"
    expect(response).to have_http_status(:ok)
    get "/analyst"
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("Accès refusé")
    get "/admin"
    expect(response).to have_http_status(:forbidden)
  end

  it "lets an analyst in the analyst home but not the admin one" do
    sign_in(user_with("analyst"))

    get "/analyst"
    expect(response).to have_http_status(:ok)
    get "/admin"
    expect(response).to have_http_status(:forbidden)
  end

  it "lets an admin in everywhere" do
    sign_in(user_with("admin"))

    %w[/ /analyst /admin].each do |path|
      get path
      expect(response).to have_http_status(:ok)
    end
  end

  it "shows each role its own navigation" do
    sign_in(user_with("analyst"))

    get "/"
    expect(response.body).to include(%(href="/analyst"))
    expect(response.body).not_to include(%(href="/admin"))
  end
end
