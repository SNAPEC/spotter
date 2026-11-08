require "rails_helper"

RSpec.describe Report, "#edit_submitted!", type: :model do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:other) { User.create!(email: "marc.petit@example.com") }
  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  let(:old_text) { "Ancien récit fictif. Suite." }
  let(:new_text) { "Récit fictif corrigé. Suite." }
  let(:edit) { { event_type: "incident", narrative_attributes: { raw_text: new_text } } }

  def submitted(mode: "confidential")
    report, = Report.start_draft!(mode: mode, user: (user if mode == "confidential"))
    report.save_draft!(event_type: "near_miss", narrative_attributes: { raw_text: old_text })
    code = travel_to(Date.new(2026, 11, 17)) { report.submit! }
    [ report, code ]
  end

  let(:report) { submitted.first }

  def analyzed(report)
    Report::Analyzer.new.call(report, revision: report.content_revision)
    report.reload
  end

  def excerpts(report)
    Analysis.where(report_id: report.id).flat_map { |analysis| analysis.proposals.values.pluck("excerpt") }.uniq
  end

  def stored_text(report)
    Narrative.find_by(report_id: report.id).raw_text
  end

  describe "while the report waits for an analyst" do
    {
      "submitted" => ->(report) { report },
      "analyzing" => ->(report) { report.tap(&:start_analysis!) },
      "in_validation" => ->(report) { Report::Analyzer.new.call(report, revision: report.content_revision) && report.reload }
    }.each do |status, reach|
      it "takes the new content and goes back to submitted from #{status}" do
        reach.call(report)
        expect(report.reload.status).to eq(status)

        report.edit_submitted!(edit, user: user)

        expect(report.reload).to be_submitted
        expect(report.event_type).to eq("incident")
        expect(stored_text(report)).to eq(new_text)
        expect(report.content_revision).to eq(1)
      end
    end

    it "replaces the analyses, whose excerpts quote the old text, and asks for a new one after commit" do
      analyzed(report)
      expect(excerpts(report)).to eq([ "Ancien récit fictif." ])
      clear_enqueued_jobs

      Report.transaction do
        report.edit_submitted!(edit, user: user)
        expect(enqueued_jobs).to be_empty
      end

      expect(Analysis.where(report_id: report.id)).to be_empty
      expect(enqueued_jobs.sole["arguments"]).to eq([ { "_aj_globalid" => report.to_global_id.to_s }, 1 ])
      perform_enqueued_jobs
      expect(excerpts(report)).to eq([ "Récit fictif corrigé." ])
      expect(report.reload).to be_in_validation
    end

    it "keeps the ownership cutoff and the submission month" do
      cutoff = report.report_ownership.cutoff_on

      travel_to(Date.new(2026, 12, 20)) { report.edit_submitted!(edit, user: user) }

      expect(ReportOwnership.find_by(report_id: report.id).cutoff_on).to eq(cutoff)
      expect(report.reload.submitted_on).to eq(Date.new(2026, 11, 1))
    end

    it "lets the anonymous declarant edit with the tracking code, which keeps working" do
      anonymous, code = submitted(mode: "anonymous")

      anonymous.edit_submitted!(edit, tracking_code: code.upcase.delete("-"))
      anonymous.edit_submitted!({ narrative_attributes: { raw_text: "Troisième version fictive." } }, tracking_code: code)

      expect(Report.find_by_tracking_code(code)).to eq(anonymous)
      expect(stored_text(anonymous)).to eq("Troisième version fictive.")
      expect(anonymous.reload.content_revision).to eq(2)
    end

    it "changes nothing, keeps the analysis and asks for none when the form comes back unchanged" do
      report.edit_submitted!(edit.merge(casualties_attributes: [ { severity: "minor", answers: { "age_range" => "over_60" } } ]), user: user)
      perform_enqueued_jobs
      casualty = report.casualties.sole
      analysis = Analysis.where(report_id: report.id).sole
      clear_enqueued_jobs

      [
        {},
        { event_type: "incident", narrative_attributes: { raw_text: new_text } },
        { casualties_attributes: [ { id: casualty.id, severity: "minor", answers: { "age_range" => "over_60" } } ] }
      ].each { |same| Report.find(report.id).edit_submitted!(same, user: user) }

      expect(report.reload).to have_attributes(content_revision: 1, status: "in_validation")
      expect(Analysis.where(report_id: report.id)).to eq([ analysis ])
      expect(enqueued_jobs).to be_empty
    end

    it "destroys a casualty on request" do
      report.edit_submitted!({ casualties_attributes: [ { severity: "minor" }, { severity: "severe" } ] }, user: user)
      kept, removed = report.casualties.order(:severity).to_a

      Report.find(report.id).edit_submitted!({ casualties_attributes: [ { id: removed.id, _destroy: "1" } ] }, user: user)

      expect(Casualty.where(report_id: report.id)).to eq([ kept ])
      expect(report.reload.content_revision).to eq(2)
    end

    # No rule requires a narrative text, before or after submission: an emptied text is stored as such.
    it "accepts an emptied narrative text" do
      report.edit_submitted!({ narrative_attributes: { raw_text: "" } }, user: user)

      expect(stored_text(report)).to eq("")
      expect(report.reload).to have_attributes(content_revision: 1, status: "submitted")
    end

    it "accepts only the content of the form" do
      expect { report.edit_submitted!({ status: "validated" }, user: user) }.to raise_error(ArgumentError)
      expect { report.edit_submitted!({ narrative_attributes: { report_id: other.id } }, user: user) }.to raise_error(ArgumentError)
      expect { report.edit_submitted!({ casualties_attributes: [ { report_id: other.id } ] }, user: user) }.to raise_error(ArgumentError)
      expect(report.reload.content_revision).to eq(0)
    end

    it "keeps nothing of an invalid edit and lets the declarant try again" do
      expect { report.edit_submitted!({ discipline: "not_a_code" }, user: user) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(report.reload).to have_attributes(discipline: nil, content_revision: 0, status: "submitted")

      report.edit_submitted!(edit, user: user)
      expect(report.reload.content_revision).to eq(1)
    end
  end

  describe "once staff took the report in charge" do
    {
      "take_charge!" => [ ->(report, analyst) { report.take_charge!(analyst) }, Report::InvalidTransition ],
      "ask_clarification!" => [ ->(report, analyst) { report.ask_clarification!(analyst, "Question fictive ?") }, Report::InvalidTransition ],
      # The decision cuts the authorship link: the declarant is no longer recognised at all.
      "validate!" => [ ->(report, analyst) { Report::Analyzer.new.call(report, revision: report.content_revision) && report.validate!(analyst) }, Report::NotAllowed ],
      "reject!" => [ ->(report, analyst) { report.reject!(analyst) }, Report::NotAllowed ]
    }.each do |action, (act, error)|
      it "is refused after #{action}" do
        act.call(report, analyst)

        expect { report.edit_submitted!(edit, user: user) }.to raise_error(error)
        expect(report.reload.content_revision).to eq(0)
        expect(report.event_type).to eq("near_miss")
      end
    end

    it "is refused to the anonymous declarant after take_charge!" do
      anonymous, code = submitted(mode: "anonymous")
      anonymous.take_charge!(analyst)

      expect { anonymous.edit_submitted!(edit, tracking_code: code) }.to raise_error(Report::InvalidTransition)
    end
  end

  describe "who may edit" do
    it "refuses another user, nobody, or a tracking code on a confidential report" do
      _, code = submitted(mode: "anonymous")

      expect { report.edit_submitted!(edit, user: other) }.to raise_error(Report::NotAllowed)
      expect { report.edit_submitted!(edit) }.to raise_error(Report::NotAllowed)
      expect { report.edit_submitted!(edit, tracking_code: code) }.to raise_error(Report::NotAllowed)
      expect { report.edit_submitted!(edit, user: user, tracking_code: code) }.to raise_error(Report::NotAllowed)
      expect(report.reload.content_revision).to eq(0)
    end

    it "refuses a user whose live ownership is on another report" do
      other_report, = Report.start_draft!(mode: "confidential", user: other)
      other_report.submit!

      expect { report.edit_submitted!(edit, user: other) }.to raise_error(Report::NotAllowed)
    end

    it "refuses the valid tracking code of another anonymous report, or a user on an anonymous report" do
      anonymous, = submitted(mode: "anonymous")
      _, other_code = submitted(mode: "anonymous")

      expect { anonymous.edit_submitted!(edit, tracking_code: other_code) }.to raise_error(Report::NotAllowed)
      expect { anonymous.edit_submitted!(edit, user: user) }.to raise_error(Report::NotAllowed)
      expect(anonymous.reload.content_revision).to eq(0)
    end

    it "refuses the owner once their account is deactivated" do
      user.update!(deactivated_at: Time.current)

      expect { report.edit_submitted!(edit, user: user) }.to raise_error(Report::NotAllowed)
    end

    it "checks the declarant before revealing the state of the report" do
      draft, = Report.start_draft!(mode: "confidential", user: user)

      expect { draft.edit_submitted!(edit, user: other) }.to raise_error(Report::NotAllowed)
      expect { draft.edit_submitted!(edit, user: user) }.to raise_error(Report::InvalidTransition)
    end
  end

  describe "an analysis run on the old text" do
    # The worst case: the new run has already put the report back in analysis when the old one ends.
    it "writes no proposals when the edit lands while the extractor runs" do
      extractor = Llm::FakeExtractor.new
      edited_id, author, content = report.id, user, edit
      extractor.define_singleton_method(:extract) do |text:, schema:|
        Report.find(edited_id).tap { |edited| edited.edit_submitted!(content, user: author) }.start_analysis!
        super(text: text, schema: schema)
      end
      clear_enqueued_jobs

      expect(Report::Analyzer.new(extractor: extractor).call(report, revision: 0)).to be_nil
      expect(Analysis.where(report_id: report.id)).to be_empty
      expect(report.reload).to be_analyzing

      perform_enqueued_jobs
      expect(excerpts(report)).to eq([ "Récit fictif corrigé." ])
    end

    it "writes nothing when its job runs after the edit" do
      report.edit_submitted!(edit, user: user)
      fresh = enqueued_jobs.select { |job| job["arguments"].last == 1 }
      queue_adapter.enqueued_jobs -= fresh

      perform_enqueued_jobs
      expect(Analysis.where(report_id: report.id)).to be_empty
      expect(report.reload).to be_submitted

      queue_adapter.enqueued_jobs += fresh
      perform_enqueued_jobs
      expect(excerpts(report)).to eq([ "Récit fictif corrigé." ])
    end

    context "when the extractor keeps failing" do
      around do |example|
        original = Rails.configuration.x.llm_extractor
        failing = Llm::FakeExtractor.new
        def failing.extract(text:, schema:) = raise(Timeout::Error, "upstream down")
        Rails.configuration.x.llm_extractor = failing
        example.run
      ensure
        Rails.configuration.x.llm_extractor = original
      end

      it "records no failure on the new content" do
        report.start_analysis!
        report.edit_submitted!(edit, user: user)
        queue_adapter.enqueued_jobs.select! { |job| job["arguments"].last == 0 }

        5.times { perform_enqueued_jobs }

        expect(Analysis.where(report_id: report.id)).to be_empty
        expect(report.reload).to be_submitted
      end
    end
  end
end
