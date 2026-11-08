class AddContentRevisionToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :content_revision, :integer, default: 0, null: false
  end
end
