require "rails_helper"

RSpec.describe "Job error logging", type: :job do
  let(:io) { StringIO.new }
  let(:id) { SecureRandom.uuid }

  around do |example|
    logger = ActiveSupport::Logger.new(io, level: :info)
    Rails.logger.broadcast_to(logger)
    example.run
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  it "logs a failing job's error without the id its message quotes" do
    stub_const("FailingJob", Class.new(ApplicationJob) {
      def perform(id) = raise(ArgumentError, "Couldn't process Report #{id}")
    })

    expect { FailingJob.perform_now(id) }.to raise_error(ArgumentError)

    expect(io.string).to include("Error performing FailingJob", "ArgumentError (Couldn't process Report [FILTERED])")
    expect(io.string).not_to include(id)
  end
end
