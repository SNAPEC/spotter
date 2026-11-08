class AddEditableUntilToReports < ActiveRecord::Migration[8.1]
  def up
    add_column :reports, :editable_until, :date
    # Only a live ownership tells the submission day: the window ends the day before its cutoff.
    # Anonymous reports, and confidential ones whose link is gone, stay without a window: not editable.
    execute <<~SQL
      UPDATE reports SET editable_until = report_ownerships.cutoff_on - 1
      FROM report_ownerships
      WHERE report_ownerships.report_id = reports.id
        AND reports.status IN (#{Report::UNDER_ANALYSIS_STATUSES.map { |value| connection.quote(value) }.join(", ")})
        AND reports.taken_in_charge = FALSE
        AND report_ownerships.cutoff_on > CURRENT_DATE
    SQL
  end

  def down
    remove_column :reports, :editable_until
  end
end
