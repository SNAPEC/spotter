require "rails_helper"

RSpec.describe "Development login", type: :request do
  it "is not routed outside development" do
    get "/dev/login"

    expect(response).to have_http_status(:not_found)
  end

  it "does not sign anyone in outside development, even when the route constraint lets the request through" do
    user = User.create!(email: "admin@example.test", role: "admin")
    # First call: the route constraint. Second: the controller's own check.
    allow(Rails.env).to receive(:development?).and_return(true, false)

    expect { post "/dev/login", params: { user_id: user.id } }.not_to change(Session, :count)
    expect(response).to have_http_status(:not_found)
  end

  context "when the environment is development" do
    let(:admin) { User.create!(email: "admin@example.test", role: "admin") }
    let(:declarant) { User.create!(email: "declarant@example.test") }

    before do
      allow(Rails.env).to receive(:development?).and_return(true)
    end

    it "lists the accounts on GET without writing anything" do
      admin
      declarant

      expect { get "/dev/login" }.not_to change { [ Session.count, User.count ] }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("admin@example.test", "declarant@example.test")
    end

    it "signs a staff account in with the passkey check already passed" do
      post "/dev/login", params: { user_id: admin.id }

      expect(response).to redirect_to(admin_root_path)
      expect(admin.sessions.sole).to be_passkey_verified
      get admin_root_path
      expect(response).to have_http_status(:ok)
    end

    it "signs a declarant in" do
      post "/dev/login", params: { user_id: declarant.id }

      expect(response).to redirect_to(root_path)
      expect(declarant.sessions.sole).not_to be_passkey_verified
    end
  end
end
