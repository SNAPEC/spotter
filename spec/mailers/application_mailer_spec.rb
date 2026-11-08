require "rails_helper"

RSpec.describe ApplicationMailer, type: :mailer do
  let(:mailer) do
    Class.new(described_class) do
      def self.name = "FictionalMailer"

      def missing_user
        User.find(0)
      end

      def broken_template
        mail(to: "lea.martin@example.com", subject: "Fictif") do |format|
          format.text { render inline: "<%= raise ArgumentError, 'fictif' %>" }
        end
      end
    end
  end

  it "lets a vanished record through unchanged, for the job to discard" do
    expect { mailer.missing_user.deliver_now }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "lets a broken template through unchanged" do
    expect { mailer.broken_template.deliver_now }.to raise_error(ActionView::Template::Error)
  end
end
