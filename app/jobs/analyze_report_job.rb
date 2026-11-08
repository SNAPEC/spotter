class AnalyzeReportJob < ApplicationJob
  queue_as :default
  # Enqueued from inside submit!'s transaction: the job must not run before the submission is visible.
  self.enqueue_after_transaction_commit = true
  retry_on ActiveRecord::ActiveRecordError, Report::Analyzer::InvalidProposals, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound, ActiveJob::DeserializationError

  def perform(report)
    Report::Analyzer.new.call(report)
  end
end
