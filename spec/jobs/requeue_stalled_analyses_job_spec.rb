require "rails_helper"
require Rails.root.join("spec/support/submittable")

RSpec.describe RequeueStalledAnalysesJob, type: :job do
  include ActiveJob::TestHelper

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  # Submitted with its analysis job lost.
  def stalled
    Report.start_draft!(mode: "anonymous").first.tap do |report|
      report.save_draft!(narrative_attributes: { raw_text: "Récit fictif d'une chute au relais." })
      submittable(report).submit!
      clear_enqueued_jobs
    end
  end

  it "analyses the submitted and analyzing reports left without analysis, and nothing else, and can run again" do
    submitted = stalled
    analyzing = stalled.tap(&:start_analysis!)
    analyzed = stalled.tap { |report| Report::Analyzer.new.call(report, revision: report.content_revision) }
    draft, = Report.start_draft!(mode: "anonymous")

    2.times { described_class.perform_now }
    perform_enqueued_jobs

    [ submitted, analyzing, analyzed ].each do |report|
      expect(Analysis.where(report_id: report.id).count).to eq(1)
      expect(report.reload).to be_in_validation
    end
    expect(draft.reload).to be_draft
  end

  it "asks for the report's current revision" do
    report = stalled
    report.update_column(:content_revision, 3)

    described_class.perform_now

    expect(enqueued_jobs.sole["arguments"].last).to eq(3)
  end

  it "is scheduled daily at 4:00, after the 3:00 jobs" do
    recurring = Rails.application.config_for(:recurring, env: "production")

    expect(recurring[:requeue_stalled_analyses]).to include(class: "RequeueStalledAnalysesJob", schedule: "every day at 4am Europe/Paris")
  end
end
