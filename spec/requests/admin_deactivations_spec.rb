require "rails_helper"

RSpec.describe "Admin deactivations", type: :request do
  let!(:admin) { User.create!(email: "admin1@example.test", role: "admin") }
  let!(:other_admin) { User.create!(email: "admin2@example.test", role: "admin") }
  let!(:analyst) { User.create!(email: "analyste@example.test", role: "analyst") }

  def sign_in_verified(user)
    post magic_link_path(user.reload.magic_link_token)
    Session.find_by!(user: user).update!(passkey_verified: true)
  end

  it "deactivates an analyst, records it and says so" do
    sign_in_verified(admin)

    expect { post admin_user_deactivation_path(analyst) }.to change(AuditEvent, :count).by(1)

    expect(response).to redirect_to(admin_root_path)
    expect(flash[:notice]).to include("analyste@example.test")
    expect(analyst.reload).to be_deactivated
  end

  it "is closed to analysts" do
    sign_in_verified(analyst)

    post admin_user_deactivation_path(other_admin)

    expect(response).to have_http_status(:forbidden)
    expect(other_admin.reload).to be_active
  end

  it "refuses an admin deactivating themselves" do
    sign_in_verified(admin)

    expect { post admin_user_deactivation_path(admin) }.not_to change(AuditEvent, :count)

    expect(response).to redirect_to(admin_root_path)
    expect(flash[:alert]).to be_present
    expect(admin.reload).to be_active
  end

  it "refuses a declarant account" do
    declarant = User.create!(email: "declarant@example.test")
    sign_in_verified(admin)

    post admin_user_deactivation_path(declarant)

    expect(flash[:alert]).to be_present
    expect(declarant.reload).to be_active
  end

  it "refuses with a flash when fewer than 2 other active admins would remain" do
    sign_in_verified(admin)

    post admin_user_deactivation_path(other_admin)

    expect(response).to redirect_to(admin_root_path)
    expect(flash[:alert]).to include("2 administrateurs")
    expect(other_admin.reload).to be_active
  end

  it "shows the button for active others only, and a label for deactivated staff" do
    analyst2 = User.create!(email: "analyste2@example.test", role: "analyst")
    analyst2.deactivate!(by: admin)
    sign_in_verified(admin)

    get admin_root_path

    expect(response.body).to include(admin_user_deactivation_path(analyst))
    expect(response.body).not_to include(admin_user_deactivation_path(admin))
    expect(response.body).not_to include(admin_user_deactivation_path(analyst2))
    expect(response.body).to include("Désactivé")
  end
end
