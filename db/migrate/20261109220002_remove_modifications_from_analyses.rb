# The report carries the final codes now: an analysis stays the snapshot of what the extractor proposed.
class RemoveModificationsFromAnalyses < ActiveRecord::Migration[8.1]
  def change
    remove_column :analyses, :modifications, :text, null: false
  end
end
