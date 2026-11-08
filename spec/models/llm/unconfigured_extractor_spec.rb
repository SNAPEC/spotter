require "rails_helper"

RSpec.describe Llm::UnconfiguredExtractor do
  include ActiveJob::TestHelper

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  around do |example|
    original = Rails.configuration.x.llm_extractor
    Rails.configuration.x.llm_extractor = described_class.new
    example.run
  ensure
    Rails.configuration.x.llm_extractor = original
  end

  it "is production's extractor" do
    expect(Rails.application.config_for(:external_services, env: "production")[:llm_extractor].constantize).to eq(described_class)
  end

  it "hands every report over to the analyst with a failed analysis and no proposal" do
    report, = Report.start_draft!(mode: "anonymous")
    report.save_draft!(narrative_attributes: { raw_text: "Récit fictif d'un rappel trop court." })
    report.submit!

    20.times do
      break if enqueued_jobs.empty?

      perform_enqueued_jobs
    end

    expect(Analysis.where(report_id: report.id).sole).to have_attributes(status: "failed", provider: "none", proposals: {})
    expect(report.reload).to be_in_validation
  end
end
