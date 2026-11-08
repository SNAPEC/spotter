require "rails_helper"

RSpec.describe AnalyzeReportJob, type: :job do
  include ActiveJob::TestHelper

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let!(:report) do
    Report.start_draft!(mode: "confidential", user: user).first.tap do |report|
      report.save_draft!(narrative_attributes: { raw_text: "Récit fictif d'un blocage de corde." })
    end
  end

  it "is enqueued by submit! with the report as its only argument" do
    expect { report.submit! }.to have_enqueued_job(described_class).with(report).exactly(:once)
    expect(enqueued_jobs.sole["arguments"]).to eq([ { "_aj_globalid" => report.to_global_id.to_s } ])
  end

  it "is enqueued only once the submission commits" do
    Report.transaction do
      report.submit!
      expect(enqueued_jobs).to be_empty
    end

    expect(enqueued_jobs.size).to eq(1)
  end

  it "is not enqueued when the submission rolls back" do
    Report.transaction do
      report.submit!
      raise ActiveRecord::Rollback
    end

    expect(enqueued_jobs).to be_empty
    expect(report.reload).to be_draft
  end

  it "analyses the report once, even when run again" do
    report.submit!
    perform_enqueued_jobs
    described_class.perform_now(report)

    analysis = Analysis.where(report_id: report.id).sole
    expect(analysis.provider).to be_present
    expect(analysis.model).to be_present
    expect(analysis.prompt_version).to be_present
    expect(report.reload).to be_in_validation
  end

  context "when the extractor keeps failing" do
    around do |example|
      original = Rails.configuration.x.llm_extractor
      failing = Llm::FakeExtractor.new
      def failing.extract(text:, schema:) = raise(Timeout::Error, "upstream echoed: #{text}")
      Rails.configuration.x.llm_extractor = failing
      example.run
    ensure
      Rails.configuration.x.llm_extractor = original
    end

    it "records a failed analysis after its last attempt and hands the report over, once" do
      report.submit!
      5.times { perform_enqueued_jobs }
      described_class.perform_now(report)

      expect(Analysis.where(report_id: report.id).sole).to have_attributes(status: "failed", proposals: {})
      expect(report.reload).to be_in_validation
    end
  end

  it "is discarded when the report no longer exists" do
    report.submit!
    report.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
    expect(Analysis.where(report_id: report.id)).to be_empty
  end
end
