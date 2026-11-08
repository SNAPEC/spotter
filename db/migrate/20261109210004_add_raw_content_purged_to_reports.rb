class AddRawContentPurgedToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :raw_content_purged, :boolean, default: false, null: false
  end
end
