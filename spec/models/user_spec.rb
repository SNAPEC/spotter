require "rails_helper"

RSpec.describe User, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "lea.martin@example.com") }

  it "stores no password and no timestamp" do
    expect(User.column_names).not_to include("password_digest", "created_at", "updated_at")
  end

  it "defaults to the declarant role" do
    expect(user.role).to eq("declarant")
  end

  it "rejects an unknown role in the model and in the database" do
    expect(User.new(email: "x@example.com", role: "boss")).not_to be_valid
    expect { user.update_column(:role, "boss") }.to raise_error(ActiveRecord::StatementInvalid, /users_role_check/)
  end

  it "rejects a malformed email" do
    expect(User.new(email: "not an email")).not_to be_valid
  end

  describe "email encryption" do
    it "does not store the email in clear" do
      raw = User.connection.select_value(User.where(id: user.id).select(:email).to_sql)

      expect(raw).not_to include("example.com")
    end

    it "finds a user by email regardless of case and surrounding spaces" do
      user

      expect(User.find_by(email: "  Lea.Martin@EXAMPLE.com ")).to eq(user)
    end
  end

  describe "roles" do
    it "tells staff apart from declarants" do
      expect(user).not_to be_staff
      expect(User.new(role: "analyst")).to be_analyst.and be_staff
      expect(User.new(role: "admin")).to be_admin.and be_staff
    end
  end

  describe "#member?" do
    it "is true until the membership expiry date included" do
      user.membership_expires_on = Date.current

      expect(user).to be_member
    end

    it "is false once the membership has expired or without a date" do
      user.membership_expires_on = Date.yesterday
      expect(user).not_to be_member

      user.membership_expires_on = nil
      expect(user).not_to be_member
    end
  end

  describe "magic link" do
    it "finds the user from a fresh token" do
      expect(User.find_by_token_for(:magic_link, user.magic_link_token)).to eq(user)
    end

    it "expires the token after 15 minutes" do
      token = user.magic_link_token

      travel 15.minutes + 1.second do
        expect(User.find_by_token_for(:magic_link, token)).to be_nil
      end
    end

    it "invalidates the token once consumed" do
      token = user.magic_link_token

      expect(user.consume_magic_link!).to be(true)
      expect(User.find_by_token_for(:magic_link, token)).to be_nil
    end

    it "lets only one of two concurrent consumers win" do
      other_copy = User.find(user.id)

      expect(user.consume_magic_link!).to be(true)
      expect(other_copy.consume_magic_link!).to be(false)
    end

    describe ".sign_in_with_magic_link" do
      it "returns the user once and refuses the same token afterwards" do
        token = user.magic_link_token

        expect(User.sign_in_with_magic_link(token)).to eq(user)
        expect(User.sign_in_with_magic_link(token)).to be_nil
      end

      it "refuses a tampered token" do
        expect(User.sign_in_with_magic_link("#{user.magic_link_token}x")).to be_nil
      end
    end
  end

  describe ".send_magic_link" do
    include ActionMailer::TestHelper

    it "creates a declarant for an unknown email and mails the link" do
      user = nil

      assert_enqueued_emails(1) { user = User.send_magic_link("nouveau@example.com") }
      expect(user).to be_persisted.and have_attributes(role: "declarant")
    end

    it "reuses the account of a known email" do
      user

      expect { User.send_magic_link("LEA.MARTIN@example.com") }.not_to change(User, :count)
    end

    it "sends nothing for a malformed email" do
      assert_no_enqueued_emails { expect(User.send_magic_link("nope")).not_to be_persisted }
    end
  end
end
