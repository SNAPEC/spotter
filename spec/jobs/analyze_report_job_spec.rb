require "rails_helper"
require Rails.root.join("spec/support/submittable")

RSpec.describe AnalyzeReportJob, type: :job do
  include ActiveJob::TestHelper

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let!(:report) do
    Report.start_draft!(mode: "confidential", user: user).first.tap do |report|
      report.save_draft!(narrative_attributes: { raw_text: "Récit fictif d'un blocage de corde." })
    end
  end

  it "is enqueued by submit! with the report and its content revision as its only arguments" do
    expect { submittable(report).submit! }.to have_enqueued_job(described_class).with(report, 0).exactly(:once)
    expect(enqueued_jobs.sole["arguments"]).to eq([ { "_aj_globalid" => report.to_global_id.to_s }, 0 ])
  end

  it "is enqueued only once the submission commits" do
    Report.transaction do
      submittable(report).submit!
      expect(enqueued_jobs).to be_empty
    end

    expect(enqueued_jobs.size).to eq(1)
  end

  it "is not enqueued when the submission rolls back" do
    Report.transaction do
      submittable(report).submit!
      raise ActiveRecord::Rollback
    end

    expect(enqueued_jobs).to be_empty
    expect(report.reload).to be_draft
  end

  it "analyses the report once, even when run again" do
    submittable(report).submit!
    perform_enqueued_jobs
    described_class.perform_now(report, report.content_revision)

    analysis = Analysis.where(report_id: report.id).sole
    expect(analysis.provider).to be_present
    expect(analysis.model).to be_present
    expect(analysis.prompt_version).to be_present
    expect(report.reload).to be_in_validation
  end

  context "when something keeps failing" do
    include ActiveSupport::Testing::TimeHelpers

    let(:calls) { [] }
    let(:reported) { [] }
    let(:subscriber) { Struct.new(:errors) { def report(error, handled:, **) = errors << [ error.message, handled ] }.new(reported) }

    around do |example|
      original = Rails.configuration.x.llm_extractor
      Rails.error.subscribe(subscriber)
      example.run
    ensure
      Rails.error.unsubscribe(subscriber)
      Rails.configuration.x.llm_extractor = original
    end

    def use_extractor(&extract)
      extractor = Llm::FakeExtractor.new
      counted = calls
      extractor.define_singleton_method(:extract) do |text:, schema:|
        counted << Time.current
        extract ? extract.call(text) : super(text: text, schema: schema)
      end
      Rails.configuration.x.llm_extractor = extractor
    end

    # Retries are enqueued while the queue drains: run until nothing is left.
    def drain
      20.times do
        break if enqueued_jobs.empty?

        job = enqueued_jobs.min_by { |enqueued| enqueued["scheduled_at"].to_s }
        travel_to(Time.zone.parse(job["scheduled_at"])) if job["scheduled_at"]
        perform_enqueued_jobs
      end
      expect(enqueued_jobs).to be_empty
    end

    def expect_handed_over
      expect(Analysis.where(report_id: report.id).sole).to have_attributes(status: "failed", proposals: {})
      expect(report.reload).to be_in_validation
    end

    it "gives an unavailable extractor about an hour, then hands the report over without error, once" do
      use_extractor { |text| raise Timeout::Error, "upstream echoed: #{text}" }
      submittable(report).submit!

      expect { drain }.not_to raise_error
      described_class.perform_now(report, report.content_revision)

      expect(calls.size).to eq(7)
      expect(reported).to eq([ [ "Report::Analyzer::ExtractionFailed", true ] ])
      # Retries carry up to 15 % jitter.
      expect(calls.each_cons(2).map { |earlier, later| later - earlier }).to all(be_between(10.minutes, 12.minutes))
      expect(calls.last - calls.first).to be_between(1.hour, 70.minutes)
      expect_handed_over
    end

    it "tries three times on any other error, then hands the report over without error" do
      use_extractor { |_text| [] }
      submittable(report).submit!

      expect { drain }.not_to raise_error

      expect(calls.size).to eq(3)
      expect(reported).to eq([ [ "Report::Analyzer::InvalidProposals", true ] ])
      expect(calls.last - calls.first).to be < 10.minutes
      expect_handed_over
    end

    it "ends without error even when recording the failure fails, and the daily sweep picks the report up again" do
      use_extractor
      broken = Rails.configuration.x.llm_extractor
      def broken.provider = raise("provider unavailable")
      submittable(report).submit!

      expect { drain }.not_to raise_error
      expect(Analysis.where(report_id: report.id)).to be_empty
      expect(report.reload).to be_analyzing
      expect(reported).to eq([ [ "RuntimeError", true ], [ "record_failure: RuntimeError", true ] ])

      use_extractor
      Report.requeue_stalled_analyses
      drain

      expect(Analysis.where(report_id: report.id).sole.status).to eq("proposed")
      expect(report.reload).to be_in_validation
    end
  end

  # Solid Queue blocks a second job with the same key until the first one ends.
  it "runs one job per report at a time" do
    other, = Report.start_draft!(mode: "anonymous")
    job = described_class.new(report, 0)

    expect(described_class.concurrency_limit).to eq(1)
    expect(job.concurrency_key).to eq(described_class.new(report, 1).concurrency_key)
    expect(job.concurrency_key).not_to eq(described_class.new(other, 0).concurrency_key)
  end

  it "is discarded when the report no longer exists" do
    submittable(report).submit!
    report.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
    expect(Analysis.where(report_id: report.id)).to be_empty
  end
end
