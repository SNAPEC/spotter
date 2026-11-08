require "rails_helper"

RSpec.describe Report::Analyzer, type: :model do
  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  let(:raw_text) { "Chute fictive au deuxième point d'une voie fictive. Personne n'a été blessé." }
  let(:report) do
    Report.start_draft!(mode: "anonymous").first.tap do |report|
      report.save_draft!(event_type: "near_miss", narrative_attributes: { raw_text: raw_text, debrief_causes: "Cause fictive." })
      report.submit!
    end
  end

  def analyze(extractor = Llm::FakeExtractor.new)
    described_class.new(extractor: extractor).call(report)
  end

  describe "#call" do
    it "stores the extractor's proposals with its provider, model and prompt version, then hands the report over for validation" do
      analysis = analyze

      expect(analysis).to be_persisted
      expect(analysis).to have_attributes(provider: "fake", model: "fake-extractor", prompt_version: "fake-v1", status: "proposed")
      expect(analysis.proposals).to include("discipline", "weather")
      expect(analysis.proposals["weather"]).to include("value", "excerpt")
      expect(report.reload).to be_in_validation
    end

    it "uses the configured extractor by default" do
      expect(described_class.new.call(report).provider).to eq("fake")
    end

    it "keeps a single analysis per prompt version" do
      first = analyze
      second = analyze

      expect(second).to eq(first)
      expect(Analysis.where(report_id: report.id).count).to eq(1)
    end

    it "picks up a report left in analysis by an interrupted run" do
      report.start_analysis!

      expect(analyze).to be_persisted
      expect(report.reload).to be_in_validation
    end

    it "leaves a report decided before the analysis alone" do
      report.reject!(analyst)

      expect(analyze).to be_nil
      expect(Analysis.where(report_id: report.id)).to be_empty
    end

    it "closes the schema at every level" do
      schemas = []
      extractor = Llm::FakeExtractor.new
      extractor.define_singleton_method(:extract) { |text:, schema:| schemas << schema; super(text: text, schema: schema) }
      analyze(extractor)

      schema = schemas.sole
      expect(schema).to include("additionalProperties" => false, "required" => schema["properties"].keys)
      schema["properties"].each_value do |property|
        expect(property).to include("additionalProperties" => false, "required" => %w[value excerpt])
      end
    end

    {
      "an extra key" => ->(proposals) { proposals["weather"]["quote"] = "Chute fictive au deuxième point" },
      "a non-string excerpt" => ->(proposals) { proposals["weather"]["excerpt"] = [ "Chute fictive" ] },
      "a missing excerpt" => ->(proposals) { proposals["weather"].delete("excerpt") },
      "a missing field" => ->(proposals) { proposals.delete("weather") },
      "a proposal that is not an object" => ->(proposals) { proposals["weather"] = "good" }
    }.each do |label, tamper|
      it "refuses #{label} and keeps the report in analysis" do
        extractor = Llm::FakeExtractor.new
        extractor.define_singleton_method(:extract) { |text:, schema:| super(text: text, schema: schema).tap(&tamper) }

        expect { analyze(extractor) }.to raise_error(Report::Analyzer::InvalidProposals)
        expect(Analysis.where(report_id: report.id)).to be_empty
        expect(report.reload).to be_analyzing
      end
    end

    it "hides the extractor's own error, which may quote the narrative" do
      extractor = Llm::FakeExtractor.new
      def extractor.extract(text:, schema:) = raise(IOError, "upstream echoed: #{text}")

      expect { analyze(extractor) }.to raise_error(Report::Analyzer::ExtractionFailed) { |error|
        expect(error.cause).to be_nil
        expect(error.message).not_to include("Chute fictive")
      }
      expect(report.reload).to be_analyzing
    end

    it "refuses proposals outside the schema and keeps the report in analysis" do
      extractor = Llm::FakeExtractor.new
      def extractor.extract(text:, schema:) = { "weather" => { "value" => "snowstorm", "excerpt" => "x" } }

      expect { analyze(extractor) }.to raise_error(Report::Analyzer::InvalidProposals)
      expect(Analysis.where(report_id: report.id)).to be_empty
      expect(report.reload).to be_analyzing
    end
  end

  describe "#record_failure" do
    it "records a failed analysis without proposals and hands the report over for manual coding, once" do
      report.start_analysis!
      first = described_class.new.record_failure(report)
      second = described_class.new.record_failure(report)

      expect(second).to eq(first)
      expect(first).to have_attributes(status: "failed", provider: "fake", proposals: {})
      expect(Analysis.where(report_id: report.id).count).to eq(1)
      expect(report.reload).to be_in_validation
    end

    it "also takes a report still waiting for its analysis" do
      expect(described_class.new.record_failure(report).status).to eq("failed")
      expect(report.reload).to be_in_validation
    end

    it "leaves a decided report alone" do
      report.reject!(analyst)

      expect(described_class.new.record_failure(report)).to be_nil
      expect(Analysis.where(report_id: report.id)).to be_empty
    end
  end

  describe "Analysis#strip_raw_excerpts!" do
    it "keeps only the value of each proposal, whatever else was stored" do
      analysis = analyze
      analysis.update!(proposals: analysis.proposals.merge("weather" => { "value" => "good", "excerpt" => "x", "quote" => "Chute fictive" }, "odd" => "Chute fictive"))

      analysis.strip_raw_excerpts!

      stored = Analysis.find(analysis.id).proposals
      expect(stored["weather"]).to eq("value" => "good")
      expect(stored["odd"]).to eq({})
      expect(Analysis.where(id: analysis.id).pick(Arel.sql("proposals::text"))).not_to include("Chute fictive", "quote", "excerpt")
    end


    it "leaves no excerpt and no modification, and keeps the coded values" do
      analysis = analyze
      analysis.update!(modifications: { "anonymized_text" => raw_text })
      values = analysis.proposals.transform_values { |proposal| proposal["value"] }

      analysis.strip_raw_excerpts!

      stored = Analysis.find(analysis.id)
      expect(stored.modifications).to eq({})
      expect(stored.proposals.transform_values { |proposal| proposal["value"] }).to eq(values)
      expect(stored.proposals.values).to all(satisfy { |proposal| !proposal.key?("excerpt") })
      expect(Analysis.where(id: analysis.id).pick(Arel.sql("proposals::text"))).not_to include("Chute fictive")
    end
  end

  describe "schema" do
    it "has a UUID id, no timestamps, and rejects unknown states at the database level" do
      analysis = analyze

      expect(Analysis.columns_hash["id"].type).to eq(:uuid)
      expect(Analysis.column_names).not_to include("created_at", "updated_at")
      { status: "lost", provider: "openai" }.each do |column, value|
        expect { Analysis.transaction(requires_new: true) { analysis.update_column(column, value) } }
          .to raise_error(ActiveRecord::StatementInvalid, /analyses_#{column}_check/)
      end
    end
  end
end
