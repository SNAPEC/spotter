require "rails_helper"

RSpec.describe Report, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let!(:taxonomy) { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }
  let(:user) { User.create!(email: "lea.martin@example.com") }

  describe "schema" do
    it "has a UUID id and neither created_at nor updated_at" do
      expect(described_class.columns_hash["id"].type).to eq(:uuid)
      expect(described_class.column_names).not_to include("created_at", "updated_at")
    end

    it "gives its dependent tables UUID ids, which do not reveal creation order" do
      [ Casualty, Narrative, ReportOwnership, Analysis, Clarification ].each do |model|
        expect(model.columns_hash["id"].type).to eq(:uuid)
      end
    end

    it "has no timestamps on its dependent tables" do
      [ Casualty, Narrative, ReportOwnership, Analysis, Clarification ].each do |model|
        expect(model.column_names).not_to include("created_at", "updated_at")
      end
    end

    it "has no column nor foreign key pointing to users" do
      connection = described_class.connection

      expect(described_class.column_names.grep(/user/)).to be_empty
      expect(connection.foreign_keys(:reports).map(&:to_table)).not_to include("users")
      %i[report_ownerships analyses clarifications].each do |table|
        expect(connection.foreign_keys(table).map(&:to_table)).not_to include("users")
        expect(connection.columns(table).map(&:name).grep(/user/)).to eq(table == :report_ownerships ? [ "user_ref" ] : [])
      end
    end

    it "rejects unknown states at the database level" do
      report, = described_class.start_draft!(mode: "anonymous")

      { status: "lost", mode: "public", event_type: "rumour" }.each do |column, value|
        expect { Report.transaction(requires_new: true) { report.update_column(column, value) } }
          .to raise_error(ActiveRecord::StatementInvalid, /reports_#{column}_check/)
      end
    end

    it "encrypts the raw narrative, the debriefing answers, the clarifications and the user reference" do
      expect(Narrative.encrypted_attributes).to include(:raw_text, :free_text_answers, *Narrative::DEBRIEF_FIELDS.map(&:to_sym))
      expect(Analysis.encrypted_attributes).to include(:proposals, :modifications)
      expect(Clarification.encrypted_attributes).to include(:body)
      expect(ReportOwnership.encrypted_attributes).to include(:user_ref)
    end

    it "stores the answers to the five debriefing questions of taxonomy v0" do
      expect(Narrative::DEBRIEF_FIELDS).to eq(%w[debrief_causes debrief_what_worked debrief_do_differently debrief_changes_made debrief_message])
      expect(Narrative.column_names).to include(*Narrative::DEBRIEF_FIELDS)
    end
  end

  describe ".start_draft!" do
    it "starts an anonymous draft with no ownership, found by its token only" do
      travel_to Date.new(2026, 11, 17) do
        report, token = described_class.start_draft!(mode: "anonymous")

        expect(report).to be_draft
        expect(report.taxonomy_version).to eq(taxonomy)
        expect(report.draft_expires_on).to eq(Date.new(2026, 12, 17))
        expect(report.report_ownership).to be_nil
        expect(token.length).to be >= 32
        expect(report.draft_token_digest).not_to include(token)
        expect(described_class.find_draft_by_token(token)).to eq(report)
      end
    end

    it "links a confidential draft to its author until the draft expires, without a token" do
      travel_to Date.new(2026, 11, 17) do
        report, token = described_class.start_draft!(mode: "confidential", user: user)

        expect(token).to be_nil
        expect(report.draft_token_digest).to be_nil
        expect(report.report_ownership.cutoff_on).to eq(Date.new(2026, 12, 18))
        expect(report.report_ownership.user_ref).to eq(user.id.to_s)
        expect(described_class.owned_by(user)).to contain_exactly(report)
      end
    end

    it "refuses a confidential draft without user and an anonymous draft with one" do
      expect { described_class.start_draft!(mode: "confidential") }.to raise_error(ArgumentError)
      expect { described_class.start_draft!(mode: "anonymous", user: user) }.to raise_error(ArgumentError)
      expect { described_class.start_draft!(mode: "public") }.to raise_error(ArgumentError)
      expect(described_class.count).to eq(0)
    end

    it "stores a different digest for each draft" do
      first, = described_class.start_draft!(mode: "anonymous")
      second, = described_class.start_draft!(mode: "anonymous")

      expect(first.draft_token_digest).not_to eq(second.draft_token_digest)
    end
  end

  describe ".find_draft_by_token" do
    it "returns nothing for a blank, unknown or expired token" do
      report, token = described_class.start_draft!(mode: "anonymous")

      expect(described_class.find_draft_by_token(nil)).to be_nil
      expect(described_class.find_draft_by_token("")).to be_nil
      expect(described_class.find_draft_by_token("not-a-token")).to be_nil
      travel_to(report.draft_expires_on + 1) { expect(described_class.find_draft_by_token(token)).to be_nil }
    end

    it "no longer finds the report once submitted" do
      report, token = described_class.start_draft!(mode: "anonymous")
      report.submit!

      expect(described_class.find_draft_by_token(token)).to be_nil
    end
  end

  describe ".owned_by" do
    it "finds only the reports linked to that user" do
      other = User.create!(email: "paul.durand@example.com")
      mine, = described_class.start_draft!(mode: "confidential", user: user)
      described_class.start_draft!(mode: "confidential", user: other)
      described_class.start_draft!(mode: "anonymous")

      expect(described_class.owned_by(user)).to contain_exactly(mine)
    end

    it "ignores an overdue link even before the daily job has cut it" do
      report, = described_class.start_draft!(mode: "confidential", user: user)
      travel_to(Date.new(2026, 11, 17)) { report.submit! }

      travel_to(Date.new(2027, 1, 15)) { expect(described_class.owned_by(user)).to contain_exactly(report) }
      travel_to(Date.new(2027, 1, 16)) { expect(described_class.owned_by(user)).to be_empty }
      expect(ReportOwnership.where(report_id: report.id)).to exist
    end

    it "ignores an expired confidential draft before the daily jobs" do
      report, = described_class.start_draft!(mode: "confidential", user: user)

      travel_to(report.draft_expires_on + 1) { expect(described_class.owned_by(user)).to be_empty }
    end

    it "finds the submitted report while the link exists, and no longer after the cutoff" do
      report, = described_class.start_draft!(mode: "confidential", user: user)
      travel_to(Date.new(2026, 11, 17)) { report.submit! }

      travel_to(Date.new(2027, 1, 15)) do
        ReportOwnership.cut_due
        expect(described_class.owned_by(user)).to contain_exactly(report)
      end
      travel_to(Date.new(2027, 1, 16)) do
        ReportOwnership.cut_due
        expect(described_class.owned_by(user)).to be_empty
      end
    end
  end

  describe "confidential draft on its last day" do
    let(:report) { described_class.start_draft!(mode: "confidential", user: user).first }

    def run_daily_jobs
      CutOwnershipsJob.perform_now
      PurgeExpiredDraftsJob.perform_now
    end

    it "is still owned and submittable on its expiry day" do
      travel_to(report.draft_expires_on) do
        run_daily_jobs

        expect(described_class.owned_by(user)).to contain_exactly(report)
        expect { report.submit! }.not_to raise_error
      end
    end

    it "loses both its link and its content the day after" do
      travel_to(report.draft_expires_on + 1) do
        run_daily_jobs

        expect(described_class.where(id: report.id)).to be_empty
        expect(ReportOwnership.where(report_id: report.id)).to be_empty
      end
    end
  end

  describe "ownership cutoff" do
    let(:report) { described_class.start_draft!(mode: "confidential", user: user).first }

    it "cannot be pushed past the day after the draft expiry" do
      expect { report.report_ownership.update!(cutoff_on: report.draft_expires_on + 2) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "cannot be pushed past 60 days from today once submitted" do
      report.submit!

      expect { report.report_ownership.update!(cutoff_on: Date.current + 61) }.to raise_error(ActiveRecord::RecordInvalid)
      expect { ReportOwnership.find_by(report_id: report.id).update!(cutoff_on: Date.current + 3650) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(report.report_ownership.reload.cutoff_on).to eq(Date.current + 60)
    end

    it "only follows the draft expiry while a draft" do
      expect { report.report_ownership.update!(cutoff_on: report.draft_expires_on) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "is frozen once submitted, even to a value within 60 days" do
      travel_to(Date.new(2026, 11, 17)) { report.submit! }

      travel_to(Date.new(2026, 11, 20)) do
        [ report.report_ownership, ReportOwnership.find_by(report_id: report.id) ].each do |ownership|
          expect { ownership.update!(cutoff_on: Date.current + 30) }.to raise_error(ActiveRecord::RecordInvalid)
          expect { ownership.reload.update!(cutoff_on: Date.current + 60) }.to raise_error(ActiveRecord::RecordInvalid)
        end
      end
      expect(ReportOwnership.where(report_id: report.id).pick(:cutoff_on)).to eq(Date.new(2027, 1, 16))
    end
  end

  describe "#save_draft!" do
    let(:report) { described_class.start_draft!(mode: "confidential", user: user).first }

    it "pushes the expiry back 30 days and keeps the ownership cutoff in sync" do
      report
      travel_to(Date.current + 10) do
        report.save_draft!(event_type: "accident", discipline: "lead")

        expect(report.reload.draft_expires_on).to eq(Date.current + 30)
        expect(report.report_ownership.reload.cutoff_on).to eq(report.draft_expires_on + 1)
        expect(report.discipline).to eq("lead")
      end
    end

    it "saves the narrative and casualties" do
      report.save_draft!(
        narrative_attributes: { raw_text: "Chute fictive au troisième point.", debrief_do_differently: "Vérifier le noeud." },
        casualties_attributes: [ { severity: "minor", answers: { "age_range" => "from_18_to_39" } } ]
      )

      expect(report.reload.narrative.raw_text).to eq("Chute fictive au troisième point.")
      expect(report.casualties.sole.severity).to eq("minor")
    end

    it "saves free-text answers in the narrative" do
      report.save_draft!(narrative_attributes: { free_text_answers: { "material_damage" => "Corde fictive coupée" } })

      expect(report.reload.narrative.free_text_answers).to eq("material_damage" => "Corde fictive coupée")
      expect(report.answers).to be_empty
      expect { report.save_draft!(answers: { "material_damage" => "Corde fictive" }) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses attributes outside the draft content" do
      expect { report.save_draft!(status: "validated") }.to raise_error(ArgumentError)
      expect { report.save_draft!(draft_expires_on: Date.current + 365) }.to raise_error(ArgumentError)
      expect(report.reload).to be_draft
    end

    it "refuses nested attributes outside the declarant's content" do
      other, = described_class.start_draft!(mode: "anonymous")

      [
        { narrative_attributes: { anonymized_text: "Version forgée" } },
        { narrative_attributes: { anonymized_debrief: { "x" => "y" } } },
        { narrative_attributes: { report_id: other.id } },
        { casualties_attributes: [ { severity: "minor", report_id: other.id } ] },
        { casualties_attributes: { "0" => { severity: "minor", unexpected: "x" } } }
      ].each do |attrs|
        expect { report.save_draft!(attrs) }.to raise_error(ArgumentError)
      end
      expect(Narrative.where(report_id: [ report.id, other.id ])).to be_empty
      expect(Casualty.where(report_id: [ report.id, other.id ])).to be_empty
    end

    it "accepts casualties as a list or as a form hash, with id and _destroy" do
      report.save_draft!(casualties_attributes: { "0" => { severity: "minor", answers: {} } })
      casualty = report.casualties.sole
      report.save_draft!(casualties_attributes: [ { id: casualty.id, _destroy: "1" } ])

      expect(report.reload.casualties).to be_empty
    end

    it "keeps its errors after a failed save and accepts the next one" do
      expect { report.save_draft!(discipline: "bogus") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(report.errors.attribute_names).to include(:discipline)

      expect { report.save_draft!(casualties_attributes: [ { severity: "bogus" } ]) }.to raise_error(ActiveRecord::RecordInvalid)

      report.save_draft!(discipline: "lead")

      expect(report.reload.discipline).to eq("lead")
      expect(report.casualties).to be_empty
    end

    it "restores the report after a casualty id that is not its own" do
      other, = described_class.start_draft!(mode: "anonymous")
      other.save_draft!(casualties_attributes: [ { severity: "minor" } ])

      expect { report.save_draft!(discipline: "lead", casualties_attributes: [ { id: other.casualties.sole.id, severity: "fatal" } ]) }
        .to raise_error(ActiveRecord::RecordNotFound)
      expect(report.discipline).to be_nil
      expect(report.changed).to be_empty

      report.save_draft!(environment: "indoor")
      expect(report.reload.environment).to eq("indoor")
    end

    it "refuses nil or malformed nested attributes with an ArgumentError" do
      [
        { narrative_attributes: nil },
        { narrative_attributes: "raw" },
        { casualties_attributes: nil },
        { casualties_attributes: [ "minor" ] }
      ].each do |attrs|
        expect { report.save_draft!(attrs) }.to raise_error(ArgumentError)
      end
    end

    it "refuses a report that is no longer a draft" do
      report.submit!

      expect { report.save_draft!(discipline: "lead") }.to raise_error(Report::InvalidTransition)
    end
  end

  describe "taxonomy validation" do
    let(:report) { described_class.start_draft!(mode: "anonymous").first }

    it "accepts option codes of its taxonomy version" do
      report.assign_attributes(discipline: "lead", environment: "outdoor", cause: "belay_error", severity: "moderate")

      expect(report).to be_valid
    end

    it "rejects codes that are not options of the matching field" do
      report.assign_attributes(discipline: "outdoor", environment: "lead", cause: "nap", severity: "lead")

      expect(report).not_to be_valid
      expect(report.errors.attribute_names).to include(:discipline, :environment, :cause, :severity)
    end

    it "validates answers with the report scope" do
      report.answers = { "weather" => "good" }
      expect(report).to be_valid

      report.answers = { "age_range" => "under_12" }
      expect(report).not_to be_valid
      expect(report.errors.details[:answers].first).to include(codes: [ "age_range.unknown_field" ])
    end

    it "validates casualties against the severity options and the casualty scope" do
      expect(report.casualties.build(severity: "fatal", answers: { "age_range" => "over_60" })).to be_valid
      expect(report.casualties.build(severity: "mild")).not_to be_valid
      expect(report.casualties.build(answers: { "weather" => "good" })).not_to be_valid
    end
  end
end
