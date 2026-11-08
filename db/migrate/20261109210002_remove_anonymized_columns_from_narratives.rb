class RemoveAnonymizedColumnsFromNarratives < ActiveRecord::Migration[8.1]
  def change
    remove_column :narratives, :anonymized_text, :text
    remove_column :narratives, :anonymized_debrief, :jsonb
  end
end
