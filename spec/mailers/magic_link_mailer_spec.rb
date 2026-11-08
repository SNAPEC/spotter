require "rails_helper"

RSpec.describe MagicLinkMailer, type: :mailer do
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
