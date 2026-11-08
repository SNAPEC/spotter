class RequeueStalledAnalysesJob < ApplicationJob
  queue_as :default
  retry_on ActiveRecord::ActiveRecordError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform
    Report.requeue_stalled_analyses
  end
end
