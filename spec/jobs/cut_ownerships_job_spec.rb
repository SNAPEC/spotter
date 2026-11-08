require "rails_helper"

RSpec.describe CutOwnershipsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }

  def owned_report(cutoff_on)
    Report.start_draft!(mode: "confidential", user: user).first.tap do |report|
      report.report_ownership.update_column(:cutoff_on, cutoff_on)
    end
  end

  it "deletes the links whose cutoff is today or past, keeps the others, and can run again" do
    past = owned_report(Date.yesterday)
    today = owned_report(Date.current)
    future = owned_report(Date.tomorrow)

    2.times { described_class.perform_now }

    expect(ReportOwnership.where(report_id: [ past.id, today.id ])).to be_empty
    expect(ReportOwnership.where(report_id: future.id)).to exist
    expect(Report.where(id: [ past.id, today.id, future.id ]).count).to eq(3)
  end

  it "is scheduled daily at 3:00" do
    recurring = Rails.application.config_for(:recurring, env: "production")

    expect(recurring[:cut_ownerships]).to include(class: "CutOwnershipsJob", schedule: "every day at 3am")
  end
end
