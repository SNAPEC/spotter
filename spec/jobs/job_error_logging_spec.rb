require "rails_helper"

RSpec.describe "Job error logging", type: :job do
  let(:io) { StringIO.new }
  let(:id) { SecureRandom.uuid }

  # Masked as the initializer masks every logger behind Rails.logger.
  around do |example|
    logger = NoIpLogging.install(ActiveSupport::Logger.new(io, level: :info))
    Rails.logger.broadcast_to(logger)
    example.run
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  it "logs a failing job's error without the id its message quotes, but with the job id" do
    stub_const("FailingJob", Class.new(ApplicationJob) {
      def perform(id) = raise(ArgumentError, "Couldn't process Report #{id}")
    })
    job = FailingJob.new(id)

    expect { job.perform_now }.to raise_error(ArgumentError)

    expect(io.string).to include("Error performing FailingJob (Job ID: #{job.job_id})")
    expect(io.string).to include("ArgumentError (Couldn't process Report [FILTERED])")
    expect(io.string.scan(id)).to be_empty
  end

  it "logs a Solid Queue error without the id its message quotes" do
    SolidQueue.instrument(:thread_error, error: ArgumentError.new("Couldn't process Report #{id}"))

    expect(io.string).to include("Error in thread", "ArgumentError Couldn't process Report [FILTERED]")
    expect(io.string).not_to include(id)
    expect(SolidQueue.logger).to eq(Rails.logger)
  end
end
