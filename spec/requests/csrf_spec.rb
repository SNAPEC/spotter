require "rails_helper"

# The test environment turns forgery protection off; these examples turn it back on.
RSpec.describe "CSRF protection", type: :request do
  let!(:admin) { User.create!(email: "admin1@example.test", role: "admin") }
  let!(:analyst) { User.create!(email: "analyste@example.test", role: "analyst") }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def csrf_token_from_page
    Nokogiri::HTML(response.body).at('meta[name="csrf-token"]')["content"]
  end

  describe "POST /login/:token" do
    let(:token) { analyst.magic_link_token }

    it "refuses a sign-in posted without the form's token, and leaves the link usable" do
      post magic_link_path(token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Session.where(user: analyst)).to be_empty

      get magic_link_path(token)
      form_token = Nokogiri::HTML(response.body).at('input[name="authenticity_token"]')["value"]
      post magic_link_path(token), params: { authenticity_token: form_token }

      expect(Session.where(user: analyst).count).to eq(1)
    end
  end

  describe "an admin action" do
    before do
      get magic_link_path(admin.magic_link_token)
      post magic_link_path(admin.magic_link_token), params: { authenticity_token: csrf_token_from_page }
      Session.find_by!(user: admin).update!(passkey_verified: true)
    end

    it "refuses a passkey reset posted without a token, and accepts it with one" do
      expect { post admin_user_passkey_reset_path(analyst) }.not_to change(AuditEvent, :count)
      expect(response).to have_http_status(:unprocessable_content)

      get admin_root_path
      expect { post admin_user_passkey_reset_path(analyst), params: { authenticity_token: csrf_token_from_page } }
        .to change(AuditEvent, :count)
    end

    it "refuses a deactivation posted with a forged token" do
      post admin_user_deactivation_path(analyst), params: { authenticity_token: "forged" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(analyst.reload).to be_active
    end
  end
end
