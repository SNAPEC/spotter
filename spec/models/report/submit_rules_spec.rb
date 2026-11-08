require "rails_helper"

RSpec.describe Report, "submission rules, casualties limit and predicates", type: :model do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }
  before { travel_to(Date.new(2026, 11, 17)) }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  let(:report) { Report.start_draft!(mode: "confidential", user: user).first }

  def messages_of(error)
    error.record.errors.full_messages
  end

  describe "#submit!" do
    it "refuses a draft without event type and without text, one error per missing field, in French" do
      error = begin
        report.submit!
      rescue ActiveRecord::RecordInvalid => e
        e
      end

      expect(error).to be_a(ActiveRecord::RecordInvalid)
      expect(messages_of(error)).to contain_exactly("Le type d’événement doit être renseigné", "Le récit doit être renseigné")
    end

    it "names only the missing field" do
      report.save_draft!(event_type: "incident")

      expect { report.submit! }.to raise_error(ActiveRecord::RecordInvalid, /Le récit doit être renseigné/)

      report.save_draft!(event_type: "", narrative_attributes: { raw_text: "Récit fictif." })
      expect { report.submit! }.to raise_error(ActiveRecord::RecordInvalid, /Le type d’événement doit être renseigné/)
    end

    it "treats a blank text as missing" do
      report.save_draft!(event_type: "incident", narrative_attributes: { raw_text: "  \n " })

      expect { report.submit! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "leaves the report unchanged and enqueues nothing when it refuses" do
      report.save_draft!(event_type: "incident")
      clear_enqueued_jobs

      expect { report.submit! }.to raise_error(ActiveRecord::RecordInvalid)

      report.reload
      expect(report).to be_draft
      expect(report.submitted_on).to be_nil
      expect(report.draft_expires_on).to be_present
      expect(ReportOwnership.find_by(report_id: report.id)).to be_present
      expect(enqueued_jobs).to be_empty
    end

    it "submits once both are there, in both modes" do
      report.save_draft!(event_type: "incident", narrative_attributes: { raw_text: "Récit fictif." })
      expect(report.submit!).to be_nil
      expect(report.reload).to be_submitted

      anonymous, = Report.start_draft!(mode: "anonymous")
      anonymous.save_draft!(event_type: "near_miss", narrative_attributes: { raw_text: "Récit fictif." })
      expect(anonymous.submit!).to be_present
    end
  end

  describe "casualties limit" do
    def casualties(count) = Array.new(count) { { severity: "minor" } }

    it "accepts #{Report::MAX_CASUALTIES} casualties" do
      report.save_draft!(casualties_attributes: casualties(3))

      expect(report.reload.casualties.size).to eq(3)
    end

    it "refuses a fourth, with a French message, and stores none of them" do
      expect { report.save_draft!(casualties_attributes: casualties(4)) }
        .to raise_error(ActiveRecord::RecordInvalid, /Les personnes blessées ne peuvent pas être plus de 3 par RETEX/)

      expect(report.reload.casualties).to be_empty
    end

    it "refuses a fourth added to three stored ones" do
      report.save_draft!(casualties_attributes: casualties(3))

      expect { report.save_draft!(casualties_attributes: casualties(1)) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(report.reload.casualties.size).to eq(3)
    end

    it "does not count the casualties marked for destruction" do
      report.save_draft!(casualties_attributes: casualties(3))
      first = report.casualties.first

      report.save_draft!(casualties_attributes: [ { id: first.id, _destroy: "1" }, { severity: "minor" } ])

      expect(report.reload.casualties.size).to eq(3)
      expect(report.casualties).not_to include(first)
    end
  end

  describe "#editable_by_declarant?" do
    let(:submitted) do
      report.save_draft!(event_type: "incident", narrative_attributes: { raw_text: "Récit fictif." })
      report.submit!
      report.reload
    end

    it "is false for a draft" do
      expect(report).not_to be_editable_by_declarant
    end

    it "is true while under analysis, not taken in charge, until the last editable day" do
      expect(submitted).to be_editable_by_declarant
      travel_to(submitted.editable_until) { expect(submitted).to be_editable_by_declarant }
      travel_to(submitted.editable_until + 1) { expect(submitted).not_to be_editable_by_declarant }
    end

    it "is false once taken in charge" do
      submitted.take_charge!(analyst)

      expect(submitted.reload).not_to be_editable_by_declarant
    end

    it "is false once decided or purged" do
      submitted.reject!(analyst)

      expect(submitted.reload).not_to be_editable_by_declarant
    end

    it "is false when the raw content is purged" do
      submitted.update_columns(raw_content_purged: true)

      expect(submitted.reload).not_to be_editable_by_declarant
    end

    it "is what edit_submitted! checks" do
      submitted.update_columns(editable_until: Date.current - 1)

      expect { submitted.edit_submitted!({ event_type: "accident" }, user: user) }.to raise_error(Report::InvalidTransition)
    end
  end

  describe "French dates" do
    it "prints month and day names" do
      date = Date.new(2026, 11, 8)

      expect(I18n.l(date, format: "%B %Y")).to eq("novembre 2026")
      expect(I18n.l(date, format: "%A %-d %B")).to eq("dimanche 8 novembre")
      expect(I18n.l(date, format: "%a %b")).to eq("dim nov.")
      expect(I18n.l(Date.new(2026, 8, 3), format: "%B")).to eq("août")
      expect(I18n.l(date)).to eq("08/11/2026")
    end
  end
end
