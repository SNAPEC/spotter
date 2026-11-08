require "rails_helper"

RSpec.describe CloseExpiredEditWindowsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  def submitted_with_window(editable_until)
    Report.start_draft!(mode: "anonymous").first.tap do |report|
      report.submit!
      report.update_column(:editable_until, editable_until)
    end
  end

  it "clears the windows whose last day is past, keeps today's and future ones, and can run again" do
    past = submitted_with_window(Date.yesterday)
    today = submitted_with_window(Date.current)
    future = submitted_with_window(Date.tomorrow)

    2.times { described_class.perform_now }

    expect(past.reload.editable_until).to be_nil
    expect(today.reload.editable_until).to eq(Date.current)
    expect(future.reload.editable_until).to eq(Date.tomorrow)
  end

  it "closes a window the day its report's ownership is cut, like CutOwnershipsJob" do
    user = User.create!(email: "lea.martin@example.com")
    report, = travel_to(Date.new(2026, 11, 17)) { Report.start_draft!(mode: "confidential", user: user) }
    travel_to(Date.new(2026, 11, 17)) { report.submit! }

    travel_to(Date.new(2027, 1, 15)) do
      described_class.perform_now
      CutOwnershipsJob.perform_now
    end
    expect(report.reload.editable_until).to eq(Date.new(2027, 1, 15))
    expect(ReportOwnership.where(report_id: report.id)).to exist

    travel_to(Date.new(2027, 1, 16)) do
      described_class.perform_now
      CutOwnershipsJob.perform_now
    end
    expect(report.reload.editable_until).to be_nil
    expect(ReportOwnership.where(report_id: report.id)).to be_empty
  end

  it "is scheduled daily at 3:00" do
    recurring = Rails.application.config_for(:recurring, env: "production")

    expect(recurring[:close_expired_edit_windows]).to include(class: "CloseExpiredEditWindowsJob", schedule: "every day at 3am Europe/Paris")
  end
end
