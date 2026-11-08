require "rails_helper"

# A job log line carries a timestamp: with the report id or the recipient next to it, the log would
# link a report to its author or date the submission to the second.
RSpec.describe "Report job logging", type: :job do
  include ActiveJob::TestHelper

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:declarant) { User.create!(email: "lea.martin@example.com") }
  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  let(:io) { StringIO.new }

  around do |example|
    logger = ActiveSupport::Logger.new(io, level: :info)
    Rails.logger.broadcast_to(logger)
    example.run
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  it "logs neither the report nor the recipient while analysing and asking for a clarification" do
    report, = Report.start_draft!(mode: "confidential", user: declarant)
    report.save_draft!(narrative_attributes: { raw_text: "Récit fictif." })
    report.submit!
    perform_enqueued_jobs only: AnalyzeReportJob
    report.reload.ask_clarification!(analyst, "Question fictive ?")
    perform_enqueued_jobs { ClarificationDigestJob.perform_now }

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(io.string).to include("AnalyzeReportJob", "ClarificationDigestJob", "ClarificationMailDeliveryJob")
    expect(io.string).not_to include(report.id)
    expect(io.string).not_to include(declarant.email, declarant.to_global_id.to_s)
  end
end
