require "rails_helper"

RSpec.describe Clarification, type: :model do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

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

      report.answer_clarification!("Réponse fictive.", user: user)
      expect(report).not_to be_awaiting_clarification
      expect(Report.find(report.id)).not_to be_awaiting_clarification
    end

    it "numbers the exchanges in order for each report" do
      report.ask_clarification!(analyst, "Première question fictive ?")
      report.answer_clarification!("Première réponse fictive.", user: user)
      report.ask_clarification!(analyst, "Seconde question fictive ?")

      expect(report.clarifications.reload.map { |c| [ c.position, c.author ] })
        .to eq([ [ 1, "analyst" ], [ 2, "declarant" ], [ 3, "analyst" ] ])
    end

    it "lets only staff ask, and the analyst open the exchange" do
      expect { report.ask_clarification!(user, "Question ?") }.to raise_error(Report::NotAllowed)
      expect { report.answer_clarification!("Réponse sans question.", user: user) }.to raise_error(Report::InvalidTransition)
      expect(report.clarifications.count).to eq(0)
    end

    it "lets the analyst post several messages in a row" do
      report.ask_clarification!(analyst, "Première question fictive ?")
      report.ask_clarification!(analyst, "Seconde question fictive ?")

      expect(report.clarifications.reload.map { |c| [ c.position, c.author ] }).to eq([ [ 1, "analyst" ], [ 2, "analyst" ] ])
      expect(report).to be_awaiting_clarification
    end

    it "lets the declarant answer in several messages" do
      report.ask_clarification!(analyst, "Question fictive ?")
      report.answer_clarification!("Début de réponse fictive.", user: user)
      report.answer_clarification!("Suite de la réponse fictive.", user: user)

      expect(report.clarifications.reload.map(&:author)).to eq(%w[analyst declarant declarant])
      expect(report).not_to be_awaiting_clarification
    end

    it "refuses a blank question or answer" do
      expect { report.ask_clarification!(analyst, " ") }.to raise_error(ActiveRecord::RecordInvalid)
      report.ask_clarification!(analyst, "Question fictive ?")
      expect { report.answer_clarification!("", user: user) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    # Validation cuts the ownership, so a late answer is refused as coming from a stranger.
    it "refuses a draft or a decided report" do
      draft, = Report.start_draft!(mode: "anonymous")
      expect { draft.ask_clarification!(analyst, "Question ?") }.to raise_error(Report::InvalidTransition)

      report.ask_clarification!(analyst, "Question fictive ?")
      report.validate!(analyst)
      expect { report.answer_clarification!("Réponse tardive.", user: user) }.to raise_error(Report::NotAllowed)
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
    it "mails only when the report starts waiting for the declarant" do
      report
      clear_enqueued_jobs
      mails = -> { enqueued_jobs.count { |job| job["job_class"] == "ClarificationMailDeliveryJob" } }

      report.ask_clarification!(analyst, "Première question fictive ?")
      report.ask_clarification!(analyst, "Seconde question fictive ?")
      expect(mails.call).to eq(1)

      report.answer_clarification!("Réponse fictive.", user: user)
      report.ask_clarification!(analyst, "Troisième question fictive ?")
      expect(mails.call).to eq(2)
    end
  end

  describe "who may answer" do
    let(:other) { User.create!(email: "marc.petit@example.com") }

    def anonymous_with_code
      anonymous, = Report.start_draft!(mode: "anonymous")
      anonymous.save_draft!(narrative_attributes: { raw_text: "Récit fictif anonyme." })
      code = anonymous.submit!
      anonymous.start_analysis!
      anonymous.ready_for_validation!
      anonymous.ask_clarification!(analyst, "Question fictive ?")
      [ anonymous, code ]
    end

    before { report.ask_clarification!(analyst, "Question fictive ?") }

    it "refuses another user on a confidential report" do
      expect { report.answer_clarification!("Réponse fictive.", user: other) }.to raise_error(Report::NotAllowed)
      expect { report.answer_clarification!("Réponse fictive.") }.to raise_error(Report::NotAllowed)
    end

    it "refuses the owner once their account is deactivated" do
      user.update!(deactivated_at: Time.current)

      expect { report.answer_clarification!("Réponse fictive.", user: user) }.to raise_error(Report::NotAllowed)
    end

    it "refuses a user whose live ownership is on another report" do
      other_report, = Report.start_draft!(mode: "confidential", user: other)
      other_report.save_draft!(narrative_attributes: { raw_text: "Autre récit fictif." })
      other_report.submit!
      expect(Report.owned_by(other)).to eq([ other_report ])

      expect { report.answer_clarification!("Réponse fictive.", user: other) }.to raise_error(Report::NotAllowed)
    end

    it "refuses the valid tracking code of another anonymous report" do
      anonymous, = anonymous_with_code
      _, other_code = anonymous_with_code

      expect { anonymous.answer_clarification!("Réponse fictive.", tracking_code: other_code) }.to raise_error(Report::NotAllowed)
      expect(anonymous.clarifications.count).to eq(1)
    end

    %i[validate! reject!].each do |decision|
      it "refuses the anonymous declarant's own code after #{decision}, its digest being gone" do
        anonymous, code = anonymous_with_code
        anonymous.public_send(decision, analyst)
        expect(anonymous.reload.tracking_code_digest).to be_nil

        expect { anonymous.answer_clarification!("Réponse tardive.", tracking_code: code) }.to raise_error(Report::NotAllowed)
      end
    end

    it "refuses the author once the ownership is overdue, even before it is deleted" do
      travel_to(report.report_ownership.cutoff_on) do
        expect(ReportOwnership.where(report_id: report.id)).to exist
        expect { report.answer_clarification!("Réponse tardive.", user: user) }.to raise_error(Report::NotAllowed)
      end
    end

    it "refuses a tracking code on a confidential report" do
      _, code = anonymous_with_code
      expect { report.answer_clarification!("Réponse fictive.", tracking_code: code) }.to raise_error(Report::NotAllowed)
      expect { report.answer_clarification!("Réponse fictive.", user: user, tracking_code: code) }.to raise_error(Report::NotAllowed)
    end

    it "accepts the anonymous declarant's code, in any typing" do
      anonymous, code = anonymous_with_code
      anonymous.answer_clarification!("Réponse anonyme fictive.", tracking_code: code.upcase.delete("-"))

      expect(anonymous.clarifications.reload.map(&:author)).to eq(%w[analyst declarant])
    end

    it "refuses an anonymous answer with a wrong or missing code, or from a user" do
      anonymous, code = anonymous_with_code
      expect { anonymous.answer_clarification!("Réponse fictive.", tracking_code: "aaaa-bbbb-cccc") }.to raise_error(Report::NotAllowed)
      expect { anonymous.answer_clarification!("Réponse fictive.", tracking_code: "") }.to raise_error(Report::NotAllowed)
      expect { anonymous.answer_clarification!("Réponse fictive.") }.to raise_error(Report::NotAllowed)
      expect { anonymous.answer_clarification!("Réponse fictive.", user: user) }.to raise_error(Report::NotAllowed)
      expect { anonymous.answer_clarification!("Réponse fictive.", user: user, tracking_code: code) }.to raise_error(Report::NotAllowed)
      expect(anonymous.clarifications.count).to eq(1)
    end

    it "checks the author before revealing the state of the thread" do
      fresh, = Report.start_draft!(mode: "confidential", user: user)
      expect { fresh.answer_clarification!("Réponse fictive.", user: other) }.to raise_error(Report::NotAllowed)
    end
  end
end
