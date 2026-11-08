require "rails_helper"

RSpec.describe AccessLog, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:analyst) { User.create!(email: "analyste@example.test", role: "analyst") }
  let(:report_id) { SecureRandom.uuid }

  it "records which staff member did what on which report, and nothing about an author" do
    log = described_class.record!(user: analyst, report: Struct.new(:id).new(report_id), action: "view")

    expect(log).to be_persisted
    expect(log).to have_attributes(user_id: analyst.id, report_id: report_id, action: "view")
    expect(described_class.column_names).to contain_exactly("id", "user_id", "report_id", "action", "recorded_on")
  end

  it "refuses an unknown action, in the model and in the database" do
    expect { described_class.record!(user: analyst, report: Struct.new(:id).new(report_id), action: "peek") }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect { described_class.insert!({ user_id: analyst.id, report_id: report_id, action: "peek", recorded_on: Date.new(2026, 11, 1) }) }
      .to raise_error(ActiveRecord::StatementInvalid, /access_logs_action_check/)
  end

  it "keeps only the month of the action" do
    log = travel_to(Time.zone.local(2026, 11, 17, 14, 32)) do
      described_class.record!(user: analyst, report: Struct.new(:id).new(report_id), action: "view")
    end

    expect(log.reload.recorded_on).to eq(Date.new(2026, 11, 1))
    expect { described_class.insert!({ user_id: analyst.id, report_id: report_id, action: "view", recorded_on: Date.new(2026, 11, 17) }) }
      .to raise_error(ActiveRecord::StatementInvalid, /access_logs_recorded_on_month_check/)
  end

  it "refuses a declarant: only staff read reports" do
    declarant = User.create!(email: "declarant@example.test")

    expect { described_class.record!(user: declarant, report: Struct.new(:id).new(report_id), action: "view") }
      .to raise_error(ActiveRecord::RecordInvalid)
  end
end
