require "rails_helper"

RSpec.describe Narrative, type: :model do
  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:report) { Report.start_draft!(mode: "anonymous").first }

  def save(narrative_attributes)
    report.save_draft!(narrative_attributes: narrative_attributes)
  end

  def error_for(narrative_attributes)
    save(narrative_attributes)
    nil
  rescue ActiveRecord::RecordInvalid => error
    error.record.narrative.errors.full_messages
  end

  it "keeps the narrative to 20,000 characters, with a message in French" do
    expect { save(raw_text: "a" * 20_000) }.not_to raise_error
    expect(error_for(raw_text: "a" * 20_001)).to eq([ "Le récit est trop long (20000 caractères au maximum)" ])
    expect(Narrative.find_by(report_id: report.id).raw_text.length).to eq(20_000)
  end

  it "keeps each debriefing answer to 5,000 characters" do
    Narrative::DEBRIEF_FIELDS.each do |field|
      expect { save(field => "a" * 5_000) }.not_to raise_error
      expect(error_for(field => "a" * 5_001)).to contain_exactly(include("trop long (5000 caractères au maximum)"))
    end
  end

  it "keeps each free-text answer to 5,000 characters" do
    code = report.taxonomy_version.free_text_codes(scope: :report).first

    expect { save(free_text_answers: { code => "a" * 5_000 }) }.not_to raise_error
    expect(error_for(free_text_answers: { code => "a" * 5_001 })).to eq([ "Les réponses libres comptent une réponse trop longue (5000 caractères au maximum)" ])
  end
end
