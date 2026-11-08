class CreateReportOwnerships < ActiveRecord::Migration[8.1]
  def change
    # The only link between a report and its author: no foreign key to users, no timestamps.
    create_table :report_ownerships do |t|
      t.references :report, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.string :user_ref, null: false
      t.date :cutoff_on, null: false
      t.index :cutoff_on
    end
  end
end
