require "rails_helper"
require "fugit"

RSpec.describe "Time zone", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  it "counts days in Paris and stores timestamps in UTC" do
    expect(Time.zone.name).to eq("Europe/Paris")
    expect(ActiveRecord.default_timezone).to eq(:utc)
  end

  # 23:30 UTC on 17 December is already 00:30 on the 18th in Paris (UTC+1 in winter).
  it "rolls a deadline over at midnight in Paris, not in UTC" do
    draft, = travel_to(Time.utc(2026, 11, 17, 12)) { Report.start_draft!(mode: "anonymous") }
    expect(draft.draft_expires_on).to eq(Date.new(2026, 12, 17))

    travel_to(Time.utc(2026, 12, 17, 22, 59)) { expect(draft).to be_open_draft }
    travel_to(Time.utc(2026, 12, 17, 23, 30)) do
      expect(draft).to be_expired_draft
      Report.purge_expired_drafts
    end
    expect(Report.where(id: draft.id)).to be_empty
  end

  it "runs every recurring task at its hour in Paris" do
    Rails.application.config_for(:recurring, env: "production").each_value do |task|
      expect(Fugit.parse(task[:schedule]).timezone&.name).to eq("Europe/Paris"), task[:class]
    end
  end
end
