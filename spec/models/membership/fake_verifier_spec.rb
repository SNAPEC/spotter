require "rails_helper"

RSpec.describe Membership::FakeVerifier do
  include ActiveSupport::Testing::TimeHelpers

  let(:verifier) { described_class.new }

  it "is the configured verifier outside production" do
    expect(Rails.configuration.x.membership_verifier).to be_a(described_class)
  end

  it "treats an address as a member until the end of the season" do
    travel_to(Date.new(2026, 11, 17)) do
      expect(verifier.call(email: "lea.martin@example.com")).to eq(valid: true, expires_on: Date.new(2027, 8, 31))
    end
    travel_to(Date.new(2027, 8, 31)) do
      expect(verifier.call(email: "lea.martin@example.com")).to eq(valid: true, expires_on: Date.new(2027, 8, 31))
    end
  end

  it "refuses an address tagged as a non-member" do
    expect(verifier.call(email: "paul.durand+nonmember@example.com")).to eq(valid: false, expires_on: nil)
  end

  it "keeps the interface of Membership::Verifier" do
    expect(verifier).to be_a(Membership::Verifier)
    expect { Membership::Verifier.new.call(email: "lea.martin@example.com") }.to raise_error(NotImplementedError)
  end
end
