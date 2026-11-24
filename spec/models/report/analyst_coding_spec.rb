require "rails_helper"
require Rails.root.join("spec/support/submittable")

RSpec.describe Report, "analyst coding", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  let(:raw_text) { "Chute fictive au deuxième point d'une voie fictive." }
  let(:report) do
    Report.start_draft!(mode: "confidential", user: user).first.tap do |report|
      report.save_draft!(
        event_type: "near_miss", discipline: nil, answers: { "weather" => "good" },
        narrative_attributes: { raw_text: raw_text }
      )
      report.submit!
    end
  end

  # Proposals the fake extractor would not give: fixed, so blanks and conflicts are known.
  def propose(report, values)
    report.analyses.create!(
      provider: "fake", model: "fake-extractor", prompt_version: "fake-v1",
      proposals: values.transform_values { |value| { "value" => value, "excerpt" => "Extrait fictif." } }
    )
  end

  def raw(table, column, id)
    ActiveRecord::Base.connection.select_value("SELECT #{column} FROM #{table} WHERE id = '#{id}'")
  end

  def coding_logs
    AccessLog.where(report_id: report.id, action: "code")
  end

  def in_validation
    report.take_charge!(analyst)
    Report::Analyzer.new.call(report, revision: report.content_revision)
    report.reload
  end

  describe "pre-fill from the extractor's proposal" do
    let(:proposals) { { "discipline" => "lead", "environment" => "outdoor", "weather" => "bad", "cause" => nil } }

    it "fills only the blanks at take-over, and never a nil proposal" do
      report.update!(environment: "indoor")
      propose(report, proposals)

      report.take_charge!(analyst)

      expect(report.reload).to have_attributes(discipline: "lead", environment: "indoor", cause: nil)
      expect(report.answers).to eq("weather" => "good")
    end

    it "fills a blank answer and keeps the declarant's one" do
      propose(report, proposals.merge("weather" => "bad", "rock_condition" => nil))
      report.update!(answers: {})
      report.take_charge!(analyst)

      expect(report.reload.answers).to eq("weather" => "bad")
    end

    it "does not touch the report while the declarant can still edit it" do
      propose(report, proposals)
      report.prefill_blanks_from(report.analyses.sole)

      expect(report.reload).to have_attributes(discipline: nil, environment: nil)
    end

    it "fills the blanks when the proposals arrive after the take-over" do
      report.take_charge!(analyst)
      expect(report.reload.discipline).to be_nil

      analysis = Report::Analyzer.new.call(report, revision: report.content_revision)

      expect(report.reload).to be_in_validation
      expect(report.discipline).to eq(analysis.proposals.dig("discipline", "value"))
      expect(report.answers["weather"]).to eq("good")
    end

    it "does not run for a report nobody took in charge: the declarant's blanks stay blank" do
      Report::Analyzer.new.call(report, revision: report.content_revision)

      expect(report.reload).to have_attributes(discipline: nil, environment: nil)
    end

    it "ignores a failed analysis" do
      report.analyses.create!(status: "failed", provider: "none", model: "none", prompt_version: "none-v1")

      expect { report.take_charge!(analyst) }.not_to raise_error
      expect(report.reload.discipline).to be_nil
    end
  end

  describe "#correct_coding!" do
    before { in_validation }

    it "corrects columns and merges answers, and records the analyst once per change" do
      report.correct_coding!(analyst, discipline: "bouldering", answers: { "weather" => "bad" })
      report.correct_coding!(analyst, discipline: "bouldering")

      expect(report.reload).to have_attributes(discipline: "bouldering")
      expect(report.answers).to include("weather" => "bad")
      expect(report.answers.keys.size).to be > 1
      expect(coding_logs.pluck(:user_id)).to eq([ analyst.id ])
    end

    it "clears a code with a blank value" do
      report.correct_coding!(analyst, discipline: "bouldering")
      report.correct_coding!(analyst, discipline: "")

      expect(report.reload.discipline).to be_nil
    end

    it "refuses a value that is not an option, and keeps the report as it was" do
      before = report.reload.discipline

      expect { report.correct_coding!(analyst, discipline: "underwater_hockey") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(report.discipline).to eq(before)
      expect(Report.find(report.id).discipline).to eq(before)
      expect(coding_logs).to be_empty
    end

    it "refuses anything that is not a code" do
      expect { report.correct_coding!(analyst, status: "validated") }.to raise_error(ArgumentError)
      expect { report.correct_coding!(analyst, anonymized_text: "Texte") }.to raise_error(ArgumentError)
      expect(report.reload).to be_in_validation
    end

    it "refuses a declarant, nobody and a deactivated account, before looking at the report" do
      admin = User.create!(email: "marc.petit@example.com", role: "admin")
      former = User.create!(email: "paul.durand@example.com", role: "analyst")
      former.deactivate!(by: admin)

      [ user, nil, former ].each do |actor|
        expect { report.correct_coding!(actor, discipline: "bouldering") }.to raise_error(Report::NotAllowed)
        expect { report.write_anonymized_text!(actor, "Texte fictif.") }.to raise_error(Report::NotAllowed)
      end
      expect(coding_logs).to be_empty
    end

    it "refuses a report not taken in charge, a draft and a decided report" do
      other, = Report.start_draft!(mode: "anonymous")
      untaken = Report.start_draft!(mode: "anonymous").first.tap { |draft| submittable(draft).submit! }

      expect { untaken.correct_coding!(analyst, discipline: "bouldering") }.to raise_error(Report::InvalidTransition)
      expect { other.correct_coding!(analyst, discipline: "bouldering") }.to raise_error(Report::InvalidTransition)
      report.reject!(analyst)
      expect { report.correct_coding!(analyst, discipline: "bouldering") }.to raise_error(Report::InvalidTransition)
      expect { report.write_anonymized_text!(analyst, "Texte fictif.") }.to raise_error(Report::InvalidTransition)
    end

    it "runs under the row lock: a report decided meanwhile is refused, whatever the copy in memory says" do
      stale = Report.find(report.id)
      before = stale.discipline
      report.reject!(analyst)

      expect(stale).to be_in_validation
      expect { stale.correct_coding!(analyst, discipline: "bouldering") }.to raise_error(Report::InvalidTransition)
      expect(Report.find(report.id).discipline).to eq(before)
      expect(coding_logs).to be_empty
    end

    it "waits for the row lock" do
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("FOR UPDATE") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        report.correct_coding!(analyst, discipline: "bouldering")
      end

      expect(queries).not_to be_empty
    end
  end

  describe "the anonymised text" do
    before { in_validation }

    it "is written by the analyst, replaced whole, cleared by a blank, and recorded" do
      report.write_anonymized_text!(analyst, "Une chute fictive sans gravité.")
      expect(report.reload.anonymized_text).to eq("Une chute fictive sans gravité.")

      report.write_anonymized_text!(analyst, "   ")
      expect(report.reload.anonymized_text).to be_nil
      expect(coding_logs.count).to eq(2)
    end

    it "stays out of reach of a plain write" do
      expect { report.update!(anonymized_text: "Texte fictif.") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(report.reload.anonymized_text).to be_nil
    end

    it "is refused when too long" do
      expect { report.write_anonymized_text!(analyst, "a" * (Report::ANONYMIZED_TEXT_MAX_LENGTH + 1)) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "is stored as ciphertext, not as the text" do
      report.write_anonymized_text!(analyst, "Une chute fictive sans gravité.")

      stored = raw("reports", "anonymized_text", report.id)
      expect(stored).to be_present
      expect(stored).not_to include("chute", "fictive")
      expect(Report.find(report.id).anonymized_text).to eq("Une chute fictive sans gravité.")
    end

    it "is encrypted without determinism: the same text gives two ciphertexts" do
      other = Report.start_draft!(mode: "anonymous").first.tap { |draft| submittable(draft).submit! }
      other.take_charge!(analyst)
      Report::Analyzer.new.call(other, revision: other.content_revision)
      [ report, other.reload ].each { |each| each.write_anonymized_text!(analyst, "Même texte fictif.") }

      expect(raw("reports", "anonymized_text", report.id)).not_to eq(raw("reports", "anonymized_text", other.id))
    end
  end

  describe "#validate!" do
    before { in_validation }

    it "refuses without an anonymised text, and decides nothing" do
      expect { report.validate!(analyst) }.to raise_error(ActiveRecord::RecordInvalid, /récit anonymisé|anonymized_text/i)

      expect(report.reload).to be_in_validation
      expect(report.narrative.raw_text).to eq(raw_text)
      expect(AccessLog.where(report_id: report.id, action: "validate")).to be_empty
    end

    it "validates with the text, keeps only that text and the coded answers" do
      report.correct_coding!(analyst, discipline: "bouldering")
      report.write_anonymized_text!(analyst, "Une chute fictive sans gravité.")

      report.validate!(analyst)

      report.reload
      expect(report).to be_validated
      expect(report.anonymized_text).to eq("Une chute fictive sans gravité.")
      expect(report.discipline).to eq("bouldering")
      expect(Narrative.where(report_id: report.id).pick(:raw_text)).to be_nil
      expect(ReportOwnership.where(report_id: report.id)).to be_empty
    end

    it "does not require the text once the raw narrative was purged at 180 days" do
      travel_to(Date.current + 181) { Report.purge_overdue_raw_content }
      expect(report.reload).to be_raw_content_purged

      expect { report.validate!(analyst) }.not_to raise_error
      expect(report.reload).to be_validated
      expect(report.anonymized_text).to be_nil
    end

    it "freezes the text once decided" do
      report.write_anonymized_text!(analyst, "Une chute fictive sans gravité.")
      report.validate!(analyst)

      expect { report.update!(anonymized_text: "Autre texte.") }.to raise_error(ActiveRecord::RecordInvalid)
      report.reload
      expect { report.write_anonymized_text!(analyst, "Autre texte.") }.to raise_error(Report::InvalidTransition)
      expect(report.reload.anonymized_text).to eq("Une chute fictive sans gravité.")
    end
  end

  describe "#reject!" do
    it "keeps no text, the analyst's included" do
      in_validation
      report.write_anonymized_text!(analyst, "Une chute fictive sans gravité.")

      report.reject!(analyst)

      expect(report.reload).to be_rejected
      expect(raw("reports", "anonymized_text", report.id)).to be_nil
    end
  end

  describe "the extractor's own text" do
    it "is refused by the analyzer: its schema has no text field" do
      extractor = Llm::FakeExtractor.new
      extractor.define_singleton_method(:extract) do |text:, schema:|
        super(text: text, schema: schema).merge("anonymized_text" => { "value" => text, "excerpt" => text })
      end

      expect { Report::Analyzer.new(extractor: extractor).call(report, revision: report.content_revision) }
        .to raise_error(Report::Analyzer::InvalidProposals)
      expect(report.analyses).to be_empty
    end

    %i[validate! reject!].each do |decision|
      it "does not survive #{decision}, even if it was stored with the proposals" do
        in_validation
        analysis = report.analyses.sole
        analysis.update!(proposals: analysis.proposals.merge("anonymized_text" => { "value" => raw_text, "excerpt" => raw_text }))
        report.write_anonymized_text!(analyst, "Texte écrit par l'analyste.")

        report.public_send(decision, analyst)

        stored = Analysis.find(analysis.id).proposals
        expect(stored).not_to have_key("anonymized_text")
        expect(stored.to_s).not_to include(raw_text)
        expect(stored.except("anonymized_text").values).to all(satisfy { |proposal| proposal.keys == [ "value" ] })
      end
    end
  end

  describe "Analysis.proposal_vs_validated" do
    it "compares, field by field, the proposal with the validated code" do
      report.take_charge!(analyst)
      report.start_analysis!
      propose(report, { "discipline" => "lead", "weather" => "bad", "cause" => nil })
      report.ready_for_validation!
      report.correct_coding!(analyst, discipline: "bouldering", answers: { "weather" => "good" })
      report.write_anonymized_text!(analyst, "Texte fictif.")
      report.validate!(analyst)

      rows = Analysis.proposal_vs_validated

      expect(rows).to contain_exactly(
        { prompt_version: "fake-v1", field: "discipline", proposed: "lead", validated: "bouldering" },
        { prompt_version: "fake-v1", field: "weather", proposed: "bad", validated: "good" },
        { prompt_version: "fake-v1", field: "cause", proposed: nil, validated: nil }
      )
    end

    it "leaves out reports not validated, and failed analyses" do
      in_validation
      expect(Analysis.proposal_vs_validated).to be_empty

      report.write_anonymized_text!(analyst, "Texte fictif.")
      report.validate!(analyst)

      expect(Analysis.proposal_vs_validated).to all(include(prompt_version: "fake-v1"))
      expect(Analysis.proposal_vs_validated).not_to be_empty
      expect(Analysis.proposal_vs_validated.flat_map(&:values).join).not_to include("Chute")
    end

    it "gives only codes: no report, no text" do
      in_validation
      report.write_anonymized_text!(analyst, "Texte fictif.")
      report.validate!(analyst)

      expect(Analysis.proposal_vs_validated.flat_map(&:keys).uniq).to match_array(%i[prompt_version field proposed validated])
    end
  end
end
