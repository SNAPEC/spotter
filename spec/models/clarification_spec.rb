require "rails_helper"

RSpec.describe Clarification, type: :model do
  include ActiveJob::TestHelper

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  let(:report) do
    Report.start_draft!(mode: "confidential", user: user).first.tap do |report|
      report.save_draft!(narrative_attributes: { raw_text: "Récit fictif." })
      report.submit!
      report.start_analysis!
      report.ready_for_validation!
    end
  end

  describe "schema" do
    it "has a UUID id, no timestamps, an encrypted body and a constrained author" do
      clarification = report.ask_clarification!(analyst, "Question fictive sur le relais ?")

      expect(described_class.columns_hash["id"].type).to eq(:uuid)
      expect(described_class.column_names).not_to include("created_at", "updated_at")
      expect(described_class.encrypted_attributes).to include(:body)
      stored = described_class.connection.select_value("SELECT body FROM clarifications WHERE id = #{described_class.connection.quote(clarification.id)}")
      expect(stored).to be_present
      expect(stored).not_to include("relais")
      expect { described_class.transaction(requires_new: true) { clarification.update_column(:author, "llm") } }
        .to raise_error(ActiveRecord::StatementInvalid, /clarifications_author_check/)
    end
  end

  describe "Report#ask_clarification! and #answer_clarification!" do
    it "waits for the declarant after a question and no longer after the answer" do
      expect(report).not_to be_awaiting_clarification

      report.ask_clarification!(analyst, "Question fictive ?")
      expect(report).to be_awaiting_clarification

      report.answer_clarification!("Réponse fictive.")
      expect(report).not_to be_awaiting_clarification
      expect(Report.find(report.id)).not_to be_awaiting_clarification
    end

    it "numbers the exchanges in order for each report" do
      report.ask_clarification!(analyst, "Première question fictive ?")
      report.answer_clarification!("Première réponse fictive.")
      report.ask_clarification!(analyst, "Seconde question fictive ?")

      expect(report.clarifications.reload.map { |c| [ c.position, c.author ] })
        .to eq([ [ 1, "analyst" ], [ 2, "declarant" ], [ 3, "analyst" ] ])
    end

    it "lets only staff ask, one question at a time, and answers only a pending question" do
      expect { report.ask_clarification!(user, "Question ?") }.to raise_error(Report::NotAllowed)
      expect { report.answer_clarification!("Réponse sans question.") }.to raise_error(Report::InvalidTransition)

      report.ask_clarification!(analyst, "Question fictive ?")
      expect { report.ask_clarification!(analyst, "Autre question ?") }.to raise_error(Report::InvalidTransition)
      expect(report.clarifications.count).to eq(1)
    end

    it "refuses a blank question or answer" do
      expect { report.ask_clarification!(analyst, " ") }.to raise_error(ActiveRecord::RecordInvalid)
      report.ask_clarification!(analyst, "Question fictive ?")
      expect { report.answer_clarification!("") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses a draft or a decided report" do
      draft, = Report.start_draft!(mode: "anonymous")
      expect { draft.ask_clarification!(analyst, "Question ?") }.to raise_error(Report::InvalidTransition)

      report.ask_clarification!(analyst, "Question fictive ?")
      report.validate!(analyst)
      expect { report.answer_clarification!("Réponse tardive.") }.to raise_error(Report::InvalidTransition)
      expect { described_class.create!(report: report, author: "declarant", body: "Réponse forcée.", position: 9) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "sends the notification after the commit, with the report as its only argument" do
      report
      clear_enqueued_jobs
      Report.transaction do
        report.ask_clarification!(analyst, "Question fictive ?")
        expect(enqueued_jobs).to be_empty
      end

      expect(enqueued_jobs.size).to eq(1)
      expect(enqueued_jobs.sole["job_class"]).to eq("ClarificationMailDeliveryJob")
      expect(enqueued_jobs.sole["arguments"].to_s).not_to include("Question", "lea.martin")
      expect(enqueued_jobs.sole["arguments"].last).to eq("args" => [ { "_aj_globalid" => report.to_global_id.to_s } ], "_aj_ruby2_keywords" => [ "args" ])
    end
  end
end
