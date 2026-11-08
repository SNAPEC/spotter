require "rails_helper"

RSpec.describe CloseExpiredEditWindowsJob, type: :job do
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

  it "is scheduled daily at 3:00" do
    recurring = Rails.application.config_for(:recurring, env: "production")

    expect(recurring[:close_expired_edit_windows]).to include(class: "CloseExpiredEditWindowsJob", schedule: "every day at 3am")
  end
end
