require "rails_helper"

RSpec.describe ClarificationMailer, type: :mailer do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: "lea.martin@example.com") }

  def bodies(mail)
    [ mail.text_part, mail.html_part ].map { |part| part.body.decoded }
  end

  it "says only that there is something new, with one sign-in link" do
    mail = described_class.digest(user)

    expect(mail.to).to eq([ "lea.martin@example.com" ])
    expect(mail.subject).to eq("Du nouveau sur Spotter")
    bodies(mail).each do |body|
      expect(body.scan(%r{https?://[^\s"<]+}).uniq).to eq([ "http://example.com/login" ])
    end
    [ mail.subject, *bodies(mail) ].each do |text|
      expect(text).not_to match(/signalement|question|retex/i)
    end
  end

  it "sends nothing to an account deactivated since the digest ran" do
    described_class.digest(user).deliver_later
    user.update!(deactivated_at: Time.current)

    expect { perform_enqueued_jobs }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "delivers through the queue and keeps the address out of the test log" do
    log = Rails.root.join("log/test.log")
    offset = File.size?(log).to_i

    described_class.digest(user).deliver_later
    expect { perform_enqueued_jobs }.to change { ActionMailer::Base.deliveries.size }.by(1)

    written = File.binread(log, nil, offset).force_encoding(Encoding::UTF_8)
    expect(written).to include("ClarificationMailDeliveryJob")
    expect(written).not_to include("lea.martin", user.to_global_id.to_s)
  end

  describe "delivery failure" do
    failing_smtp = Class.new do
      def initialize(_settings); end

      def deliver!(mail)
        raise Net::SMTPFatalError.new(Net::SMTP::Response.parse("550 5.1.1 <#{mail.to.first}>: unknown recipient"))
      end
    end

    broken_delivery = Class.new do
      def initialize(_settings); end

      def deliver!(_mail)
        raise ArgumentError, "unexpected"
      end
    end

    around do |example|
      ActionMailer::Base.add_delivery_method(:broken_delivery, broken_delivery)
      ActionMailer::Base.add_delivery_method(:failing_smtp, failing_smtp)
      described_class.delivery_method = :failing_smtp
      example.run
    ensure
      described_class.delivery_method = ActionMailer::Base.delivery_method
    end

    it "raises an error that names neither the address nor the user" do
      expect { described_class.digest(user).deliver_now }.to raise_error(ApplicationMailer::DeliveryFailed) { |error|
        expect(error.cause).to be_nil
        expect(error.message).to eq("ApplicationMailer::DeliveryFailed")
        expect(error.full_message(highlight: false)).not_to include("lea.martin", "unknown recipient")
      }
    end

    def notified_report
      TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish!
      analyst = User.create!(email: "chloe.bernard@example.com", role: "analyst")
      report = Report.start_draft!(mode: "confidential", user: user).first.tap do |report|
        report.save_draft!(narrative_attributes: { raw_text: "Récit fictif." })
        report.submit!
        report.start_analysis!
        report.ready_for_validation!
        report.ask_clarification!(analyst, "Question fictive ?")
      end
      clear_enqueued_jobs
      Report.notify_declarants
      expect(report.reload).to be_declarant_notified
      report
    end

    it "retries three times, then hands the user's reports back to the next digest without failing" do
      report = notified_report

      expect { 3.times { perform_enqueued_jobs } }.not_to raise_error
      expect(enqueued_jobs).to be_empty
      expect(performed_jobs.count { |job| job["job_class"] == "ClarificationMailDeliveryJob" }).to eq(3)
      expect(report.reload).not_to be_declarant_notified
    end

    it "ends the same way on any other error, so no failed job keeps the user's GlobalID" do
      described_class.delivery_method = :broken_delivery
      report = notified_report

      expect { 3.times { perform_enqueued_jobs } }.not_to raise_error
      expect(enqueued_jobs).to be_empty
      expect(performed_jobs.count { |job| job["job_class"] == "ClarificationMailDeliveryJob" }).to eq(3)
      expect(report.reload).not_to be_declarant_notified
    end
  end
end
