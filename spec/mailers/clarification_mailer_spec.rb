require "rails_helper"

RSpec.describe ClarificationMailer, type: :mailer do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }
  let(:raw_text) { "Récit fictif d'une chute au relais." }
  let(:question) { "Question fictive sur le type de noeud ?" }

  def submitted(mode)
    Report.start_draft!(mode: mode, user: (user if mode == "confidential")).first.tap do |report|
      report.save_draft!(narrative_attributes: { raw_text: raw_text })
      travel_to(Date.new(2026, 11, 17)) { report.submit! }
    end
  end

  def bodies(mail)
    [ mail.text_part, mail.html_part ].map { |part| part.body.decoded }
  end

  it "sends the declarant one link and nothing of the report" do
    report = submitted("confidential")
    travel_to(Date.new(2026, 11, 20)) do
      report.ask_clarification!(analyst, question)
      mail = described_class.requested(report)

      expect(mail.to).to eq([ "lea.martin@example.com" ])
      expect(mail.subject).to eq("Une question sur l’un de vos signalements")
      bodies(mail).each do |body|
        expect(body.scan(%r{https?://[^\s"<]+}).uniq).to eq([ "http://example.com/" ])
        expect(body).not_to include("relais", "noeud", report.id)
      end
      expect(mail.subject).not_to include("noeud")
    end
  end

  it "sends nothing in anonymous mode" do
    report = submitted("anonymous")

    travel_to(Date.new(2026, 11, 20)) do
      report.ask_clarification!(analyst, question)
      expect { perform_enqueued_jobs }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  it "sends nothing once the cutoff is reached, even before the daily job cuts the link" do
    report = submitted("confidential")

    travel_to(report.report_ownership.cutoff_on) do
      report.ask_clarification!(analyst, question)
      expect { perform_enqueued_jobs }.not_to change { ActionMailer::Base.deliveries.size }
      expect(ReportOwnership.where(report_id: report.id)).to exist
    end
  end

  it "sends nothing once the link is cut" do
    report = submitted("confidential")
    ReportOwnership.where(report_id: report.id).delete_all

    travel_to(Date.new(2026, 11, 20)) do
      report.ask_clarification!(analyst, question)
      expect { perform_enqueued_jobs }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  it "delivers through the queue and keeps the address out of the test log" do
    report = submitted("confidential")
    log = Rails.root.join("log/test.log")
    offset = File.size?(log).to_i

    travel_to(Date.new(2026, 11, 20)) do
      report.ask_clarification!(analyst, question)
      expect { perform_enqueued_jobs }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    written = File.binread(log, nil, offset).force_encoding(Encoding::UTF_8)
    expect(written).to include("ClarificationMailDeliveryJob")
    expect(written).not_to include("lea.martin")
  end

  describe "delivery failure" do
    failing_smtp = Class.new do
      def initialize(_settings); end

      def deliver!(mail)
        raise Net::SMTPFatalError.new(Net::SMTP::Response.parse("550 5.1.1 <#{mail.to.first}>: unknown recipient"))
      end
    end

    around do |example|
      ActionMailer::Base.add_delivery_method(:failing_smtp, failing_smtp)
      described_class.delivery_method = :failing_smtp
      example.run
    ensure
      described_class.delivery_method = ActionMailer::Base.delivery_method
    end

    it "raises an error that names neither the address nor the user" do
      report = submitted("confidential")
      travel_to(Date.new(2026, 11, 20)) { report.ask_clarification!(analyst, question) }

      expect { perform_enqueued_jobs }.to raise_error(ClarificationMailer::DeliveryFailed) { |error|
        expect(error.cause).to be_nil
        expect(error.message).to eq("ClarificationMailer::DeliveryFailed")
        expect(error.full_message(highlight: false)).not_to include("lea.martin", "unknown recipient")
      }
    end
  end
end
