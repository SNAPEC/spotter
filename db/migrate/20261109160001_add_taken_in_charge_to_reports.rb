class AddTakenInChargeToReports < ActiveRecord::Migration[8.1]
  def up
    add_column :reports, :taken_in_charge, :boolean, default: false, null: false
    # Reports already questioned or decided by staff were taken in charge.
    execute <<~SQL
      UPDATE reports SET taken_in_charge = TRUE
      WHERE status IN (#{Report::DECIDED_STATUSES.map { |value| connection.quote(value) }.join(", ")})
        OR id IN (SELECT report_id FROM clarifications WHERE author = 'analyst')
    SQL
  end

  def down
    remove_column :reports, :taken_in_charge
  end
end
