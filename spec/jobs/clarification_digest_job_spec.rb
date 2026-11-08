require "rails_helper"
require "fugit"

RSpec.describe ClarificationDigestJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  let(:lea) { User.create!(email: "lea.martin@example.com") }
  let(:marc) { User.create!(email: "marc.petit@example.com") }

  def in_validation(mode, user: nil)
    Report.start_draft!(mode: mode, user: user).first.tap do |report|
      report.save_draft!(narrative_attributes: { raw_text: "Récit fictif." })
      report.submit!
      report.start_analysis!
      report.ready_for_validation!
    end
  end

  def asked(user)
    in_validation("confidential", user: user).tap { |report| report.ask_clarification!(analyst, "Question fictive ?") }
  end

  def digest_recipients
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { described_class.perform_now }
    ActionMailer::Base.deliveries.flat_map(&:to)
  end

  it "sends nothing when the question is asked" do
    report = in_validation("confidential", user: lea)
    clear_enqueued_jobs
    report.ask_clarification!(analyst, "Question fictive ?")

    expect(enqueued_jobs).to be_empty
  end

  it "sends one mail per declarant, whatever the number of reports" do
    2.times { asked(lea) }
    asked(marc)

    expect(digest_recipients).to contain_exactly("lea.martin@example.com", "marc.petit@example.com")
  end

  it "sends nothing twice for the same waiting round" do
    report = asked(lea)
    digest_recipients

    report.ask_clarification!(analyst, "Seconde question fictive ?")
    expect(digest_recipients).to be_empty
    expect(report.reload).to be_declarant_notified
  end

  it "opens a new round with a question after an answer" do
    report = asked(lea)
    digest_recipients

    report.answer_clarification!("Réponse fictive.", user: lea)
    expect(digest_recipients).to be_empty
    report.ask_clarification!(analyst, "Nouvelle question fictive ?")

    expect(digest_recipients).to eq([ "lea.martin@example.com" ])
  end

  it "queues mails that carry only the user" do
    report = asked(lea)
    clear_enqueued_jobs
    described_class.perform_now

    expect(enqueued_jobs.sole["job_class"]).to eq("ClarificationMailDeliveryJob")
    expect(enqueued_jobs.sole["arguments"].last).to eq("args" => [ { "_aj_globalid" => lea.to_global_id.to_s } ], "_aj_ruby2_keywords" => [ "args" ])
    expect(enqueued_jobs.sole.to_s).not_to include(report.id)
  end

  it "mails a user with a new round on another report, besides an already notified one" do
    asked(lea)
    digest_recipients
    other = asked(lea)

    expect(digest_recipients).to eq([ "lea.martin@example.com" ])
    expect(other.reload).to be_declarant_notified
  end

  it "does not let an invalid report hold back the others" do
    broken = asked(lea)
    broken.update_column(:discipline, "inexistante")
    asked(marc)

    expect(broken.reload).not_to be_valid
    expect(digest_recipients).to contain_exactly("lea.martin@example.com", "marc.petit@example.com")
  end

  it "leaves the reports unmarked when the mail cannot be queued, and sends it on the next run" do
    report = asked(lea)
    failing_adapter = Class.new(ActiveJob::QueueAdapters::AbstractAdapter) do
      def enqueue(_job) = raise(ActiveJob::EnqueueError, "queue unavailable")
    end.new
    allow(ClarificationMailDeliveryJob).to receive(:queue_adapter).and_return(failing_adapter)

    expect { described_class.perform_now }.not_to raise_error
    expect(report.reload).not_to be_declarant_notified
    expect(enqueued_jobs.map { |job| job["job_class"] }).to include("ClarificationDigestJob")

    allow(ClarificationMailDeliveryJob).to receive(:queue_adapter).and_call_original
    expect(digest_recipients).to eq([ "lea.martin@example.com" ])
    expect(report.reload).to be_declarant_notified
  end

  it "sends nothing to a deactivated account" do
    report = asked(lea)
    lea.update!(deactivated_at: Time.current)

    expect(digest_recipients).to be_empty
    expect(report.reload).not_to be_declarant_notified
  end

  it "sends nothing once the link is cut or due" do
    cut = asked(lea)
    ReportOwnership.where(report_id: cut.id).delete_all
    due = asked(marc)

    travel_to(due.report_ownership.cutoff_on) do
      expect(digest_recipients).to be_empty
    end
  end

  it "leaves anonymous reports alone" do
    anonymous = in_validation("anonymous")
    anonymous.ask_clarification!(analyst, "Question fictive ?")

    expect(digest_recipients).to be_empty
    expect(anonymous.reload).not_to be_declarant_notified
  end

  it "sends nothing for a decided report, which keeps no trace of a notice" do
    report = asked(lea)
    digest_recipients
    report.validate!(analyst)

    expect(digest_recipients).to be_empty
    expect(report.reload).not_to be_declarant_notified
  end

  it "is scheduled daily at 7:00, Paris time" do
    recurring = Rails.application.config_for(:recurring, env: "production")

    expect(recurring[:clarification_digest]).to include(class: "ClarificationDigestJob")
    cron = Fugit.parse_cron(recurring[:clarification_digest][:schedule])
    expect(cron.timezone.name).to eq("Europe/Paris")
    expect(cron.next_time(Time.utc(2026, 11, 17, 12)).to_t.utc).to eq(Time.utc(2026, 11, 18, 6))
  end
end
