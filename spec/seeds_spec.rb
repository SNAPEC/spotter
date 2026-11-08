require "rails_helper"

RSpec.describe "db/seeds" do
  def load_seeds
    capture_stdout { Rails.application.load_seed }
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  def counts
    [ User, Report, Narrative, Casualty, Analysis, Clarification, ReportOwnership, TaxonomyVersion ].to_h { |model| [ model.name, model.count ] }
  end

  it "is idempotent: a second run creates nothing" do
    load_seeds
    first = counts
    load_seeds

    expect(counts).to eq(first)
  end

  it "creates the four accounts, all on the reserved example.test domain" do
    load_seeds

    expect(User.pluck(:email)).to contain_exactly(
      "declarant@example.test", "analyste@example.test", "admin@example.test", "admin2@example.test"
    )
    expect(User.pluck(:email)).to all(end_with("@example.test"))
    expect(User.where(role: "admin").count).to eq(2)
  end

  it "covers every status, mode and event type with at least 12 reports" do
    load_seeds

    expect(Report.count).to be >= 12
    expect(Report.distinct.pluck(:status)).to match_array(Report::STATUSES)
    expect(Report.distinct.pluck(:mode)).to match_array(Report::MODES)
    expect(Report.distinct.pluck(:event_type)).to match_array(Report::EVENT_TYPES)
  end

  it "has victims, fake analyses and an open clarification request" do
    load_seeds

    expect(Casualty.count).to be > 0
    expect(Analysis.count).to be > 0
    expect(Report.all.select(&:awaiting_clarification?)).not_to be_empty
  end

  it "keeps authorship out of decided reports and leaves no text on them" do
    load_seeds

    Report.decided.each do |report|
      expect(report.report_ownership).to be_nil
      expect(report.narrative.raw_text).to be_nil
    end
  end

  it "seeds no accounts nor reports in production" do
    allow(Rails.env).to receive(:production?).and_return(true)
    load_seeds

    expect(User.count).to eq(0)
    expect(Report.count).to eq(0)
    expect(TaxonomyVersion.current).to be_present
  end
end
