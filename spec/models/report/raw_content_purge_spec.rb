require "rails_helper"
require Rails.root.join("spec/support/decidable")

RSpec.describe Report, ".purge_overdue_raw_content", type: :model do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  # Submitted on 17 November 2026, so submitted_on is 1 November: the purge is due 180 days after that.
  let(:submission_day) { Date.new(2026, 11, 17) }
  let(:due_day) { Date.new(2026, 11, 1) + 180 }

  def submitted(mode: "confidential")
    travel_to(submission_day) do
      report, = Report.start_draft!(mode: mode, user: (user if mode == "confidential"))
      report.save_draft!(
        event_type: "near_miss",
        answers: { "weather" => "good" },
        narrative_attributes: Narrative::DEBRIEF_FIELDS.index_with { "Réponse fictive." }
          .merge(raw_text: "Récit fictif.", free_text_answers: { "material_damage" => "Corde fictive coupée" }),
        casualties_attributes: [ { severity: "minor", answers: { "age_range" => "over_60" } } ]
      )
      code = report.submit!
      [ report, code ]
    end
  end

  def in_validation
    report, = submitted
    travel_to(submission_day) do
      Report::Analyzer.new.call(report, revision: report.content_revision)
      report.ask_clarification!(analyst, "Question fictive ?")
    end
    report.reload
  end

  def purge_on(day)
    travel_to(day) { Report.purge_overdue_raw_content }
  end

  it "falls no later than 180 days after the submission day, and not the day before it is due" do
    report = in_validation

    purge_on(due_day - 1)
    expect(report.reload.raw_content_purged).to be(false)
    expect(Narrative.find_by(report_id: report.id).raw_text).to eq("Récit fictif.")

    purge_on(due_day)
    expect(report.reload.raw_content_purged).to be(true)
    expect(due_day).to be <= submission_day + 180
  end

  it "purges what a decision purges, keeps the status and the coded answers, and can run again" do
    report = in_validation
    narrative_id = report.narrative.id

    2.times { purge_on(due_day) }

    narrative = Narrative.find(narrative_id)
    expect(Narrative.where(id: narrative_id).pick(:raw_text, *Narrative::DEBRIEF_FIELDS)).to all(be_nil)
    expect(narrative.free_text_answers).to eq({})
    expect(Clarification.where(report_id: report.id)).to be_empty
    analysis = Analysis.where(report_id: report.id).sole
    expect(analysis.proposals.to_s).not_to include("excerpt", "Récit fictif")
    expect(ReportOwnership.where(report_id: report.id)).to be_empty
    expect(report.reload).to have_attributes(
      status: "in_validation", tracking_code_digest: nil, draft_token_digest: nil, editable_until: nil,
      declarant_notified: false, answers: { "weather" => "good" }
    )
    expect(report.casualties.sole).to have_attributes(severity: "minor", answers: { "age_range" => "over_60" })
    expect(AccessLog.where(report_id: report.id).pluck(:action)).to eq([ "ask_clarification" ])
  end

  it "leaves the tracking code of an anonymous report unusable" do
    report, code = submitted(mode: "anonymous")

    purge_on(due_day)

    expect(Report.find_by_tracking_code(code)).to be_nil
    expect(report.reload.raw_content_purged).to be(true)
  end

  it "lets the analyst code and decide the report afterwards" do
    report = in_validation
    purge_on(due_day)

    travel_to(due_day) { validate_with_text!(report, analyst) }

    expect(report.reload).to be_validated
  end

  it "hands a report still waiting for its analysis over for manual coding" do
    report, = submitted
    clear_enqueued_jobs
    purge_on(due_day)

    travel_to(due_day) do
      Report.requeue_stalled_analyses
      perform_enqueued_jobs
    end

    expect(Analysis.where(report_id: report.id).sole.status).to eq("failed")
    expect(report.reload).to be_in_validation
  end

  it "keeps an analysis running during the purge from writing excerpts of the purged text" do
    report, = submitted
    clear_enqueued_jobs
    extractor = Llm::FakeExtractor.new
    extractor.define_singleton_method(:extract) do |text:, schema:|
      Report.purge_overdue_raw_content
      super(text: text, schema: schema)
    end

    travel_to(due_day) do
      expect(Report::Analyzer.new(extractor: extractor).call(report, revision: report.content_revision)).to be_nil
    end

    expect(Analysis.where(report_id: report.id)).to be_empty
    expect(report.reload).to have_attributes(raw_content_purged: true, status: "analyzing")
  end

  context "when a report cannot be purged" do
    let(:reported) { [] }
    let(:subscriber) { Struct.new(:errors) { def report(error, **) = errors << error }.new(reported) }

    around do |example|
      Rails.error.subscribe(subscriber)
      example.run
    ensure
      Rails.error.unsubscribe(subscriber)
    end

    it "purges the others, and one whose answers no longer pass the checks" do
      stuck = in_validation
      stuck.analyses.sole.update_column(:model, "")
      outdated = in_validation
      outdated.update_column(:answers, { "retired_field" => "x" })
      other = in_validation

      purge_on(due_day)

      expect([ outdated, other ].map { |report| report.reload.raw_content_purged }).to eq([ true, true ])
      expect(stuck.reload.raw_content_purged).to be(false)
      expect(Narrative.find_by(report_id: stuck.id).raw_text).to eq("Récit fictif.")
      expect(reported.map(&:message)).to eq([ "ActiveRecord::RecordInvalid on report #{stuck.id}" ])
    end
  end

  it "leaves drafts and decided reports alone" do
    draft, = travel_to(submission_day) { Report.start_draft!(mode: "anonymous") }
    decided = in_validation
    travel_to(submission_day) { decided.reject!(analyst) }

    purge_on(due_day)

    expect(draft.reload).to have_attributes(status: "draft", raw_content_purged: false)
    expect(decided.reload).to have_attributes(status: "rejected")
  end

  it "keeps the declarant and the analyst from writing raw content back, and leaves the report out of the digest" do
    report = in_validation
    report.update_column(:declarant_notified, false)
    purge_on(due_day)

    travel_to(due_day) do
      expect { report.edit_submitted!({ narrative_attributes: { raw_text: "Récit fictif réinjecté." } }, user: user) }
        .to raise_error(Report::NotAllowed)
      expect { report.ask_clarification!(analyst, "Question fictive tardive ?") }.to raise_error(Report::InvalidTransition)
      expect(Report.awaiting_declarant_notice).to be_empty
    end
    expect(Narrative.find_by(report_id: report.id).raw_text).to be_nil
  end

  it "refuses an edit of a purged report even to a declarant still recognised" do
    report, code = submitted(mode: "anonymous")
    report.update_columns(raw_content_purged: true, editable_until: due_day)

    travel_to(due_day) do
      expect { report.edit_submitted!({ event_type: "accident" }, tracking_code: code) }.to raise_error(Report::InvalidTransition)
    end
  end
end
