class AnalyzeReportJob < ApplicationJob
  queue_as :default
  # The log line would carry the report id with the exact time of submission, which the month rounding hides.
  self.log_arguments = false
  # Enqueued from inside submit!'s and edit_submitted!'s transactions: the job must not run before the change is visible.
  self.enqueue_after_transaction_commit = true

  # After the last attempt the analyst codes the report by hand rather than wait for it forever, and the
  # job ends without error: a failed execution would keep the report's id in the queue's tables. Should
  # recording the failure fail too, Report.requeue_stalled_analyses picks the report up again.
  FALLBACK = ->(job, _error) do
    Report::Analyzer.new.record_failure(job.arguments.first, revision: job.arguments.second)
  rescue StandardError
    nil
  end

  # Later declarations take precedence: an unavailable extractor gets about an hour, anything else three quick tries.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3, &FALLBACK
  retry_on Report::Analyzer::ExtractionFailed, wait: 10.minutes, attempts: 7, &FALLBACK
  discard_on ActiveRecord::RecordNotFound, ActiveJob::DeserializationError

  # The revision is the content the job was enqueued for: a run that outlives an edit writes nothing.
  def perform(report, revision)
    Report::Analyzer.new.call(report, revision: revision)
  end
end
