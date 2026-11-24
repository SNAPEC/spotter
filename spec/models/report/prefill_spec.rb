require "rails_helper"
require Rails.root.join("spec/support/submittable")

RSpec.describe Report, "pre-filling blanks from the extractor", type: :model do
  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  let(:report) do
    Report.start_draft!(mode: "confidential", user: user).first.tap do |report|
      report.save_draft!(event_type: "near_miss", narrative_attributes: { raw_text: "Chute fictive." })
      report.submit!
    end
  end

  def analyze
    Report::Analyzer.new.call(report, revision: report.content_revision)
  end

  it "pre-fills when a question takes the report over" do
    analyze
    report.reload.ask_clarification!(analyst, "Question fictive ?")

    expect(report.reload.discipline).not_to be_nil
  end

  it "pre-fills at a take-over that follows a question asked before the analysis" do
    report.ask_clarification!(analyst, "Question fictive ?")
    analyze
    report.reload.take_charge!(analyst)

    expect(report.reload.discipline).not_to be_nil
  end

  it "refuses coding until the analysis is over, so a late proposal never overwrites a correction" do
    report.take_charge!(analyst)

    expect { report.correct_coding!(analyst, discipline: "") }.to raise_error(Report::InvalidTransition)
    expect { report.write_anonymized_text!(analyst, "Texte fictif.") }.to raise_error(Report::InvalidTransition)

    analyze
    report.reload.correct_coding!(analyst, discipline: "")
    expect(report.reload.discipline).to be_nil
  end

  it "does not fill a field the analyst left blank at the decision" do
    analyze
    report.reload.take_charge!(analyst)
    report.correct_coding!(analyst, discipline: "")
    report.write_anonymized_text!(analyst, "Texte fictif.")
    report.validate!(analyst)

    expect(report.reload.discipline).to be_nil
  end
end
