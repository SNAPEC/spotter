require "rails_helper"

RSpec.describe RecoveryCode, type: :model do
  let(:user) { User.create!(email: "analyste@example.com", role: "analyst") }

  it "stores no timestamp" do
    expect(RecoveryCode.column_names).not_to include("created_at", "updated_at")
  end

  describe "User#generate_recovery_codes!" do
    it "returns 10 distinct codes" do
      codes = user.generate_recovery_codes!

      expect(codes.size).to eq(10)
      expect(codes.uniq.size).to eq(10)
    end

    it "stores none of them in clear" do
      codes = user.generate_recovery_codes!
      stored = RecoveryCode.connection.select_values("SELECT digest FROM recovery_codes")

      expect(stored.size).to eq(10)
      codes.each do |code|
        normalized = code.delete("-")
        expect(stored.join).not_to include(code)
        expect(stored.join).not_to include(normalized)
      end
    end

    it "replaces the previous codes" do
      old_codes = user.generate_recovery_codes!
      user.generate_recovery_codes!

      expect(user.recovery_codes.count).to eq(10)
      expect(user.use_recovery_code!(old_codes.first)).to be(false)
    end
  end

  describe "User#use_recovery_code!" do
    it "accepts a code once, then deletes it" do
      code = user.generate_recovery_codes!.first

      expect(user.use_recovery_code!(code)).to be(true)
      expect(user.recovery_codes.count).to eq(9)
      expect(user.use_recovery_code!(code)).to be(false)
    end

    it "ignores case, spaces and dashes" do
      code = user.generate_recovery_codes!.first

      expect(user.use_recovery_code!(" #{code.upcase.tr("-", " ")} ")).to be(true)
    end

    it "refuses another user's code and junk" do
      other = User.create!(email: "autre@example.com", role: "analyst")
      code = other.generate_recovery_codes!.first
      user.generate_recovery_codes!

      expect(user.use_recovery_code!(code)).to be(false)
      expect(user.use_recovery_code!("")).to be(false)
      expect(user.use_recovery_code!(nil)).to be(false)
    end
  end
end
