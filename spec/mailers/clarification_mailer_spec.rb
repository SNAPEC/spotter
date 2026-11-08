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

    around do |example|
      ActionMailer::Base.add_delivery_method(:failing_smtp, failing_smtp)
      described_class.delivery_method = :failing_smtp
      example.run
    ensure
      described_class.delivery_method = ActionMailer::Base.delivery_method
    end

    it "raises an error that names neither the address nor the user" do
      described_class.digest(user).deliver_later

      expect { perform_enqueued_jobs }.to raise_error(ClarificationMailer::DeliveryFailed) { |error|
        expect(error.cause).to be_nil
        expect(error.message).to eq("ClarificationMailer::DeliveryFailed")
        expect(error.full_message(highlight: false)).not_to include("lea.martin", "unknown recipient")
      }
    end
  end
end
