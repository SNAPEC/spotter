require "rails_helper"

RSpec.describe PurgeExpiredDraftsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }

  def draft(mode: "confidential")
    Report.start_draft!(mode: mode, user: (user if mode == "confidential")).first.tap do |report|
      report.save_draft!(
        narrative_attributes: { raw_text: "Récit fictif." },
        casualties_attributes: [ { severity: "minor" } ]
      )
    end
  end

  it "deletes drafts that expired before today with their dependents, and can run again" do
    expired = draft
    expired_anonymous = draft(mode: "anonymous")
    last_day = draft
    [ expired, expired_anonymous ].each { |report| report.update_column(:draft_expires_on, Date.yesterday) }
    last_day.update_column(:draft_expires_on, Date.current)

    2.times { described_class.perform_now }

    gone = [ expired.id, expired_anonymous.id ]
    expect(Report.where(id: gone)).to be_empty
    expect(Narrative.where(report_id: gone)).to be_empty
    expect(Casualty.where(report_id: gone)).to be_empty
    expect(ReportOwnership.where(report_id: gone)).to be_empty
    expect(Report.where(id: last_day.id)).to exist
  end

  it "never touches a submitted report" do
    submitted = draft
    submitted.submit!
    submitted.update_column(:draft_expires_on, Date.current - 90)

    described_class.perform_now

    expect(Report.where(id: submitted.id)).to exist
    expect(submitted.narrative.reload.raw_text).to eq("Récit fictif.")
  end

  it "is scheduled daily at 3:00" do
    recurring = Rails.application.config_for(:recurring, env: "production")

    expect(recurring[:purge_expired_drafts]).to include(class: "PurgeExpiredDraftsJob", schedule: "every day at 3am Europe/Paris")
  end
end
