class AddTakenInChargeToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :taken_in_charge, :boolean, default: false, null: false
  end
end
