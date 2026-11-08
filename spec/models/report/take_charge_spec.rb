require "rails_helper"

RSpec.describe Report, "taking in charge", type: :model do
  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  let(:report) do
    Report.start_draft!(mode: "confidential", user: user).first.tap do |report|
      report.save_draft!(narrative_attributes: { raw_text: "Récit fictif." })
      report.submit!
    end
  end

  def take_charge_logs
    AccessLog.where(report_id: report.id, action: "take_charge")
  end

  describe "#take_charge!" do
    it "marks the report as taken in charge and records who did it, once" do
      expect(report).not_to be_taken_in_charge

      report.take_charge!(analyst)
      report.take_charge!(User.create!(email: "marc.petit@example.com", role: "admin"))

      expect(report.reload).to be_taken_in_charge
      expect(take_charge_logs.pluck(:user_id)).to eq([ analyst.id ])
      expect(report).to be_submitted
    end

    it "works in each status under analysis" do
      report.take_charge!(analyst)
      analyzing = Report.start_draft!(mode: "anonymous").first.tap { |other| other.submit!; other.start_analysis! }
      in_validation = Report.start_draft!(mode: "anonymous").first.tap { |other| other.submit!; Report::Analyzer.new.call(other) }

      [ analyzing, in_validation ].each { |other| other.take_charge!(analyst) }

      expect([ report, analyzing, in_validation ].map { |taken| taken.reload.taken_in_charge? }).to all(be(true))
    end

    it "refuses a declarant or nobody, before looking at the report" do
      draft, = Report.start_draft!(mode: "confidential", user: user)

      expect { report.take_charge!(user) }.to raise_error(Report::NotAllowed)
      expect { draft.take_charge!(nil) }.to raise_error(Report::NotAllowed)
      expect(report.reload).not_to be_taken_in_charge
      expect(take_charge_logs).to be_empty
    end

    it "refuses a draft or a decided report" do
      draft, = Report.start_draft!(mode: "confidential", user: user)
      report.reject!(analyst)

      expect { draft.take_charge!(analyst) }.to raise_error(Report::InvalidTransition)
      expect { report.take_charge!(analyst) }.to raise_error(Report::InvalidTransition)
      expect(take_charge_logs).to be_empty
    end
  end

  describe "other staff actions" do
    it "take the report in charge with a question" do
      report.ask_clarification!(analyst, "Question fictive ?")

      expect(report.reload).to be_taken_in_charge
      expect(take_charge_logs).to be_empty
    end

    { validate!: "in_validation", reject!: "submitted" }.each do |decision, status|
      it "take the report in charge with #{decision}, and keep it so after the purge" do
        Report::Analyzer.new.call(report) if status == "in_validation"
        report.public_send(decision, analyst)

        expect(report.reload).to be_taken_in_charge
      end
    end
  end
end
