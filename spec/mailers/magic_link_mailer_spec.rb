require "rails_helper"

RSpec.describe MagicLinkMailer, type: :mailer do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:mail) { MagicLinkMailer.with(user: user).sign_in }

  def token_in(text)
    text[%r{http://example\.com/login/([^\s"<]+)}, 1]
  end

  it "sends a French email to the user" do
    expect(mail.to).to eq([ "lea.martin@example.com" ])
    expect(mail.subject).to eq("Votre lien de connexion à Spotter")
  end

  it "contains a working sign-in URL in both parts" do
    [ mail.text_part, mail.html_part ].each do |part|
      expect(User.find_by_token_for(:magic_link, token_in(part.body.decoded))).to eq(user)
    end
  end

  it "sends nothing to a deactivated account" do
    admins = %w[a1 a2].map { |name| User.create!(email: "#{name}@example.com", role: "admin") }
    staff = User.create!(email: "analyste@example.com", role: "analyst")
    queued = MagicLinkMailer.with(user: staff).sign_in
    staff.deactivate!(by: admins.first)

    expect { queued.deliver_now }.not_to change(ActionMailer::Base.deliveries, :size)
  end

  it "delivers through the queue and keeps the address and the user out of the test log" do
    log = Rails.root.join("log/test.log")
    offset = File.size?(log).to_i

    User.send_magic_link(user.email)
    expect { perform_enqueued_jobs }.to change { ActionMailer::Base.deliveries.size }.by(1)

    written = File.binread(log, nil, offset).force_encoding(Encoding::UTF_8)
    expect(written).to include("ApplicationMailDeliveryJob")
    expect(written).not_to include("lea.martin", user.to_global_id.to_s)
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
      expect { mail.deliver_now }.to raise_error(ApplicationMailer::DeliveryFailed) { |error|
        expect(error.cause).to be_nil
        expect(error.full_message(highlight: false)).not_to include("lea.martin", "unknown recipient")
      }
    end

    it "retries three times, then gives up without failing, so no failed job keeps the user's GlobalID" do
      User.send_magic_link(user.email)

      expect { 3.times { perform_enqueued_jobs } }.not_to raise_error
      expect(enqueued_jobs).to be_empty
      expect(performed_jobs.count { |job| job["job_class"] == "ApplicationMailDeliveryJob" }).to eq(3)
    end
  end

  describe MagicLinkLogObserver do
    let(:io) { StringIO.new }

    around do |example|
      original = Rails.logger
      Rails.logger = Logger.new(io)
      example.run
    ensure
      Rails.logger = original
    end

    it "logs the sign-in URL and not the recipient" do
      described_class.delivered_email(mail)

      expect(token_in(io.string)).to eq(token_in(mail.text_part.body.decoded))
      expect(io.string).not_to include("lea.martin")
    end
  end
end
