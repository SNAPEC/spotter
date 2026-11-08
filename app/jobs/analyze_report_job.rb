class AnalyzeReportJob < ApplicationJob
  queue_as :default
  # The log line would carry the report id with the exact time of submission, which the month rounding hides.
  self.log_arguments = false
  # Enqueued from inside submit!'s transaction: the job must not run before the submission is visible.
  self.enqueue_after_transaction_commit = true
  # After the last attempt, the analyst codes the report by hand rather than wait for it forever.
  retry_on ActiveRecord::ActiveRecordError, Report::Analyzer::InvalidProposals, Report::Analyzer::ExtractionFailed,
    wait: :polynomially_longer, attempts: 3 do |job, _error|
    Report::Analyzer.new.record_failure(job.arguments.first, revision: job.arguments.second)
  end
  discard_on ActiveRecord::RecordNotFound, ActiveJob::DeserializationError

  # The revision is the content the job was enqueued for: a run that outlives an edit writes nothing.
  def perform(report, revision)
    Report::Analyzer.new.call(report, revision: revision)
  end
end
