class AnalyzeReportJob < ApplicationJob
  queue_as :default
  # Enqueued from inside submit!'s transaction: the job must not run before the submission is visible.
  self.enqueue_after_transaction_commit = true
  # After the last attempt, the analyst codes the report by hand rather than wait for it forever.
  retry_on ActiveRecord::ActiveRecordError, Report::Analyzer::InvalidProposals, Report::Analyzer::ExtractionFailed,
    wait: :polynomially_longer, attempts: 3 do |job, _error|
    Report::Analyzer.new.record_failure(job.arguments.first)
  end
  discard_on ActiveRecord::RecordNotFound, ActiveJob::DeserializationError

  def perform(report)
    Report::Analyzer.new.call(report)
  end
end
