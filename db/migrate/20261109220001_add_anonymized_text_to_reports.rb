# The analyst's anonymised narrative, encrypted by the model: the only text kept after a validation.
class AddAnonymizedTextToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :anonymized_text, :text
  end
end
