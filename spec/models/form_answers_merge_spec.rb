require "rails_helper"

RSpec.describe "Merge of form answers per step", type: :model do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }
  before { travel_to(Date.new(2026, 11, 17)) }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:report) { Report.start_draft!(mode: "confidential", user: user).first }

  describe "#save_draft!" do
    before do
      report.save_draft!(
        answers: { "clients_count" => 4, "environment" => "indoor" },
        narrative_attributes: { raw_text: "Récit fictif.", free_text_answers: { "material_damage" => "Corde fictive" } }
      )
    end

    it "keeps the answers a step does not post" do
      report.save_draft!(answers: { "instructors_count" => "2" })

      expect(report.reload.answers).to eq("clients_count" => 4, "environment" => "indoor", "instructors_count" => 2)
    end

    it "replaces a posted answer" do
      report.save_draft!(answers: { "clients_count" => "7" })

      expect(report.reload.answers).to include("clients_count" => 7, "environment" => "indoor")
    end

    it "removes an answer posted blank and keeps the others" do
      report.save_draft!(answers: { "environment" => "", "clients_count" => nil })

      expect(report.reload.answers).to eq({})
      report.save_draft!(answers: { "instructors_count" => "1" })
      report.save_draft!(answers: { "instructors_count" => "" })
      expect(report.reload.answers).to eq({})
    end

    it "keeps a stored answer when the step posts no answers at all" do
      report.save_draft!(event_type: "incident")

      expect(report.reload.answers).to eq("clients_count" => 4, "environment" => "indoor")
      expect(report.narrative.free_text_answers).to eq("material_damage" => "Corde fictive")
    end

    it "merges free-text answers and removes the one posted blank" do
      report.save_draft!(narrative_attributes: { free_text_answers: { "material_damage" => "" } })

      expect(report.reload.narrative.free_text_answers).to eq({})
      expect(report.narrative.raw_text).to eq("Récit fictif.")
    end

    it "keeps the free-text answers when only the text is posted" do
      report.save_draft!(narrative_attributes: { raw_text: "Autre récit." })

      expect(report.reload.narrative.free_text_answers).to eq("material_damage" => "Corde fictive")
    end

    it "leaves the stored answers when the posted ones are refused" do
      expect { report.save_draft!(answers: { "instructors_count" => "deux" }) }.to raise_error(ActiveRecord::RecordInvalid)

      expect(report.reload.answers).to eq("clients_count" => 4, "environment" => "indoor")
    end
  end

  describe "#edit_submitted!" do
    let(:report) do
      draft = Report.start_draft!(mode: "confidential", user: user).first
      draft.save_draft!(
        event_type: "near_miss", answers: { "clients_count" => 4 },
        narrative_attributes: { raw_text: "Récit fictif. Suite.", free_text_answers: { "material_damage" => "Corde fictive" } }
      )
      draft.submit!
      Report::Analyzer.new.call(draft, revision: draft.content_revision)
      draft.reload
    end

    it "merges the posted answers and keeps the analysis, which never read them" do
      expect(report.analyses).not_to be_empty

      report.edit_submitted!({ answers: { "environment" => "indoor" } }, user: user)

      expect(report.reload.answers).to eq("clients_count" => 4, "environment" => "indoor")
      expect(report.content_revision).to eq(0)
      expect(report.analyses).not_to be_empty
    end

    it "merges free-text answers without going back to analysis" do
      report.edit_submitted!({ narrative_attributes: { free_text_answers: { "material_damage" => "Autre corde fictive" } } }, user: user)

      expect(report.reload.narrative.free_text_answers).to eq("material_damage" => "Autre corde fictive")
      expect(report.content_revision).to eq(0)
      expect(report.analyses).not_to be_empty
    end

    it "treats a form sent back with the same values, as strings, as unchanged" do
      report
      clear_enqueued_jobs
      expect {
        report.edit_submitted!(
          { answers: { "clients_count" => "4", "environment" => "" },
            narrative_attributes: { raw_text: "Récit fictif. Suite.", free_text_answers: { "material_damage" => "Corde fictive", "other" => "" } } },
          user: user
        )
      }.not_to have_enqueued_job(AnalyzeReportJob)

      expect(report.reload.content_revision).to eq(0)
      expect(report.analyses).not_to be_empty
    end

    it "removes an answer posted blank" do
      report.edit_submitted!({ answers: { "clients_count" => "" } }, user: user)

      expect(report.reload.answers).to eq({})
      expect(report.analyses).not_to be_empty
    end

    it "still sends the report back to analysis when the text changed" do
      report.edit_submitted!({ answers: { "environment" => "indoor" }, narrative_attributes: { raw_text: "Récit corrigé. Suite." } }, user: user)

      expect(report.reload.content_revision).to eq(1)
      expect(report.analyses).to be_empty
      expect(report.answers).to eq("clients_count" => 4, "environment" => "indoor")
      expect(report.narrative.free_text_answers).to eq("material_damage" => "Corde fictive")
    end
  end
end
