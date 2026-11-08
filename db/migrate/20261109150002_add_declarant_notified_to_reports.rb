class AddDeclarantNotifiedToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :declarant_notified, :boolean, default: false, null: false
  end
end
