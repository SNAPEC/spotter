require "rails_helper"

RSpec.describe Report::Lifecycle, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  # v0 has no free-text casualty field: one is added so its refusal in casualty answers is exercised.
  before do
    version = TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml"))
    version.fields.create!(code: "injury_detail", group: "casualty", kind: "text", scope: "casualty", position: 99, label: "Précision")
    version.publish!
  end

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }

  def draft(mode: "confidential")
    report, = Report.start_draft!(mode: mode, user: (user if mode == "confidential"))
    report.save_draft!(
      event_type: "near_miss",
      answers: { "weather" => "good", "clients_count" => 4 },
      narrative_attributes: Narrative::DEBRIEF_FIELDS.index_with { "Réponse fictive." }
        .merge(raw_text: "Récit fictif.", free_text_answers: { "material_damage" => "Corde fictive coupée" }),
      casualties_attributes: [ { severity: "minor", answers: { "age_range" => "over_60" } } ]
    )
    report
  end

  def in_validation(mode: "confidential")
    draft(mode: mode).tap do |report|
      report.submit!
      Report::Analyzer.new.call(report)
    end
  end

  describe "#submit!" do
    it "rounds the submission to the month and cuts the link 60 days after the submission day" do
      report = draft
      travel_to(Date.new(2026, 11, 17)) { expect(report.submit!).to be_nil }

      expect(report.reload).to be_submitted
      expect(report.submitted_on).to eq(Date.new(2026, 11, 1))
      expect(report.report_ownership.cutoff_on).to eq(Date.new(2027, 1, 16))
      expect(report.draft_expires_on).to be_nil
    end

    it "returns a tracking code in anonymous mode and stores only its digest" do
      report = draft(mode: "anonymous")
      code = report.submit!

      expect(code).to be_present
      expect(report.reload.tracking_code_digest).to be_present
      expect(report.tracking_code_digest).not_to include(code)
      expect(report.draft_token_digest).to be_nil
      expect(report.report_ownership).to be_nil
      expect(Report.find_by_tracking_code(code)).to eq(report)
      expect(Report.find_by_tracking_code(code.upcase.delete("-"))).to eq(report)
      expect(Report.find_by_tracking_code("")).to be_nil
    end

    it "refuses an expired draft" do
      report = draft
      travel_to(report.draft_expires_on + 1) do
        expect { report.submit! }.to raise_error(Report::InvalidTransition)
      end
    end
  end

  describe "transitions" do
    it "follows draft, submitted, analyzing, in_validation, validated" do
      report = draft
      report.submit!
      report.start_analysis!
      report.ready_for_validation!
      report.validate!(analyst)

      expect(report.reload).to be_validated
    end

    it "refuses any step out of order" do
      report = draft

      expect { report.validate!(analyst) }.to raise_error(Report::InvalidTransition)
      expect { report.reject!(analyst) }.to raise_error(Report::InvalidTransition)
      expect { report.start_analysis! }.to raise_error(Report::InvalidTransition)
      expect { report.ready_for_validation! }.to raise_error(Report::InvalidTransition)
      report.submit!
      expect { report.submit! }.to raise_error(Report::InvalidTransition)
      expect { report.validate!(analyst) }.to raise_error(Report::InvalidTransition)
      expect(report.reload).to be_submitted
    end

    it "checks the stored state, not a stale copy" do
      report = draft
      Report.find(report.id).submit!

      expect { report.submit! }.to raise_error(Report::InvalidTransition)
    end

    it "lets an analyst reject a submitted report before the end of the analysis" do
      report = draft
      report.submit!
      report.reject!(analyst)

      expect(report.reload).to be_rejected
      expect { report.validate!(analyst) }.to raise_error(Report::InvalidTransition)
    end

    it "lets only staff validate or reject" do
      report = in_validation

      expect { report.validate!(user) }.to raise_error(Report::NotAllowed)
      expect { report.reject!(nil) }.to raise_error(Report::NotAllowed)
      expect(report.reload).to be_in_validation
    end
  end

  describe "access trail" do
    { validate!: "validate", reject!: "reject" }.each do |decision, action|
      it "records who decided with #{decision}, and nothing when the transition fails" do
        report = in_validation
        report.public_send(decision, analyst)

        expect(AccessLog.where(report_id: report.id).pluck(:user_id, :action)).to eq([ [ analyst.id, action ] ])
        expect { report.public_send(decision, analyst) }.to raise_error(Report::InvalidTransition)
        expect(AccessLog.where(report_id: report.id).count).to eq(1)
      end
    end

    it "records who asked for a clarification, and nothing when a question is pending" do
      report = in_validation
      report.ask_clarification!(analyst, "Question fictive ?")

      expect(AccessLog.where(report_id: report.id).pluck(:user_id, :action)).to eq([ [ analyst.id, "ask_clarification" ] ])
      expect { report.ask_clarification!(analyst, "Autre question fictive ?") }.to raise_error(Report::InvalidTransition)
      expect(AccessLog.where(report_id: report.id).count).to eq(1)
    end
  end

  describe "decided report" do
    %i[validate! reject!].each do |decision|
      it "refuses raw text, debriefing answers and casualty changes after #{decision}" do
        report = in_validation
        report.public_send(decision, analyst)
        narrative = Narrative.find_by(report_id: report.id)
        casualty = report.casualties.sole

        expect { narrative.update!(raw_text: "Nouveau récit fictif") }.to raise_error(ActiveRecord::RecordInvalid)
        expect { narrative.update!(debrief_message: "Message fictif") }.to raise_error(ActiveRecord::RecordInvalid)
        expect { narrative.update!(free_text_answers: { "material_damage" => "Texte fictif réinjecté" }) }.to raise_error(ActiveRecord::RecordInvalid)
        expect { report.update!(narrative_attributes: { raw_text: "Récit fictif réinjecté" }) }.to raise_error(ActiveRecord::RecordInvalid)
        expect { report.casualties.create!(severity: "minor") }.to raise_error(ActiveRecord::RecordInvalid)
        expect { casualty.update!(severity: "fatal") }.to raise_error(ActiveRecord::RecordInvalid)
        expect { casualty.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
        expect(Narrative.where(report_id: report.id).pick(:raw_text, :debrief_message)).to eq([ nil, nil ])
        expect(Casualty.where(report_id: report.id).pluck(:severity)).to eq([ "minor" ])
      end
    end

    %i[validate! reject!].each do |decision|
      it "refuses excerpts and modifications written back to the analysis after #{decision}" do
        report = in_validation
        report.public_send(decision, analyst)
        analysis = Analysis.find(report.analyses.sole.id)
        kept = analysis.proposals

        expect { analysis.update!(modifications: { "anonymized_text" => "Récit fictif réinjecté" }) }.to raise_error(ActiveRecord::RecordInvalid)
        analysis.reload
        expect { analysis.update!(proposals: kept.merge("cause" => { "value" => "other", "excerpt" => "Récit fictif" })) }
          .to raise_error(ActiveRecord::RecordInvalid)
        analysis.reload
        expect { analysis.update!(proposals: kept.merge("odd" => "Récit fictif")) }.to raise_error(ActiveRecord::RecordInvalid)
        analysis.reload
        expect { analysis.update!(status: "reviewed", proposals: kept.merge("cause" => { "value" => "other" })) }.not_to raise_error
        expect(Analysis.find(analysis.id).modifications).to be_empty
        expect(Analysis.find(analysis.id).proposals.to_s).not_to include("Récit fictif")
      end
    end

    it "refuses a status change outside the lifecycle" do
      report = in_validation

      expect { report.update!(status: "validated") }.to raise_error(ActiveRecord::RecordInvalid)
      expect { Report.create!(mode: "anonymous", status: "submitted", taxonomy_version: TaxonomyVersion.current) }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect(Report.find(report.id)).to be_in_validation
      expect(Narrative.find_by(report_id: report.id).raw_text).to eq("Récit fictif.")
    end
  end

  describe "purge at the end of the analysis" do
    %i[validate! reject!].each do |decision|
      %w[confidential anonymous].each do |mode|
        it "leaves no raw text, no ownership and no digest after #{decision} (#{mode})" do
          report = in_validation(mode: mode)
          report.update_column(:draft_token_digest, "leftover")
          narrative_id = report.narrative.id
          report.analyses.sole.update!(modifications: { "anonymized_text" => "Récit fictif retouché." })
          expect(report.analyses.sole.proposals.to_s).to include("Récit fictif.")
          report.ask_clarification!(analyst, "Question fictive ?")
          report.answer_clarification!("Réponse fictive.")

          report.public_send(decision, analyst)

          narrative = Narrative.find(narrative_id)
          expect(narrative.raw_text).to be_nil
          Narrative::DEBRIEF_FIELDS.each { |field| expect(narrative[field]).to be_nil }
          expect(narrative.free_text_answers).to eq({})
          expect(Narrative.connection.select_value("SELECT free_text_answers FROM narratives WHERE id = '#{narrative_id}'")).not_to include("Corde")
          expect(Narrative.where(id: narrative_id).pick(:raw_text, *Narrative::DEBRIEF_FIELDS)).to all(be_nil)
          expect(ReportOwnership.where(report_id: report.id)).to be_empty
          expect(Report.owned_by(user)).to be_empty
          expect(Report.where(id: report.id).pick(:tracking_code_digest, :draft_token_digest)).to eq([ nil, nil ])
          expect(Report.find(report.id).answers).to eq("weather" => "good", "clients_count" => 4)
          expect(report.casualties.sole.reload.answers).to eq("age_range" => "over_60")
          expect(report.casualties.sole.severity).to eq("minor")
          expect(Clarification.where(report_id: report.id)).to be_empty
          expect(Analysis.where(report_id: report.id).pluck(:modifications)).to eq([ {} ])
          expect(Analysis.where(report_id: report.id).sole.proposals.to_s).not_to include("excerpt", "Récit fictif")
          expect(Analysis.where(report_id: report.id).sole.proposals).to include("weather" => { "value" => be_present })
        end
      end
    end
  end

  describe "encryption at rest" do
    def raw(table, column, id)
      Narrative.connection.select_value("SELECT #{column} FROM #{table} WHERE id = '#{id}'")
    end

    it "stores free-text answers, excerpts and modifications as ciphertext" do
      report = in_validation
      analysis = report.analyses.sole
      analysis.update!(modifications: { "anonymized_text" => "Récit retouché fictif." })

      expect(report.narrative.reload.free_text_answers).to eq("material_damage" => "Corde fictive coupée")
      expect(raw("narratives", "free_text_answers", report.narrative.id)).not_to include("Corde", "material_damage")
      expect(raw("analyses", "proposals", analysis.id)).not_to include("excerpt", "Récit fictif", "weather")
      expect(raw("analyses", "modifications", analysis.id)).not_to include("anonymized_text", "retouché")
      expect(analysis.reload.proposals["weather"]).to include("excerpt")
      expect(analysis.modifications).to eq("anonymized_text" => "Récit retouché fictif.")
    end
  end

  describe "free-text codes" do
    let(:report) { draft }

    it "are refused in the answers of a report and of a casualty, decided or not" do
      expect { report.update!(answers: { "material_damage" => "Texte fictif" }) }.to raise_error(ActiveRecord::RecordInvalid)
      expect { report.casualties.sole.update!(answers: { "injury_detail" => "Détail fictif" }) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "are accepted in the narrative only for known text fields of the report scope, as strings" do
      narrative = report.narrative

      [ { "weather" => "good" }, { "injury_detail" => "Détail fictif" }, { "unknown" => "x" }, { "material_damage" => 3 } ].each do |answers|
        expect { narrative.update!(free_text_answers: answers) }.to raise_error(ActiveRecord::RecordInvalid)
      end
      expect(narrative.reload.free_text_answers).to eq("material_damage" => "Corde fictive coupée")
    end
  end
end
