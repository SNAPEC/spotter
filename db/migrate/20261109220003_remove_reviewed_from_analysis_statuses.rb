class RemoveReviewedFromAnalysisStatuses < ActiveRecord::Migration[8.1]
  def up
    replace_status_check(Analysis::STATUSES)
  end

  def down
    replace_status_check(%w[proposed reviewed failed])
  end

  private
    def replace_status_check(statuses)
      remove_check_constraint :analyses, name: "analyses_status_check"
      add_check_constraint :analyses, "status IN (#{statuses.map { |value| connection.quote(value) }.join(", ")})", name: "analyses_status_check"
    end
end
