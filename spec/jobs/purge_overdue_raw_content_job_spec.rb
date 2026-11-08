require "rails_helper"

RSpec.describe PurgeOverdueRawContentJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  it "purges the raw content of undecided reports once due, and can run again" do
    report, = travel_to(Date.new(2026, 11, 17)) do
      Report.start_draft!(mode: "anonymous").tap do |draft, _token|
        draft.save_draft!(narrative_attributes: { raw_text: "Récit fictif." })
        draft.submit!
      end
    end

    travel_to(Date.new(2026, 11, 1) + 180) { 2.times { described_class.perform_now } }

    expect(report.reload).to have_attributes(raw_content_purged: true, status: "submitted")
    expect(Narrative.find_by(report_id: report.id).raw_text).to be_nil
  end

  it "is scheduled daily at 3:00" do
    recurring = Rails.application.config_for(:recurring, env: "production")

    expect(recurring[:purge_overdue_raw_content]).to include(class: "PurgeOverdueRawContentJob", schedule: "every day at 3am Europe/Paris")
  end
end
