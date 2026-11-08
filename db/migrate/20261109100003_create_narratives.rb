class CreateNarratives < ActiveRecord::Migration[8.1]
  def change
    create_table :narratives do |t|
      t.references :report, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.text :raw_text
      t.text :debrief_causes
      t.text :debrief_what_worked
      t.text :debrief_do_differently
      t.text :debrief_changes_made
      t.text :debrief_message
      t.text :anonymized_text
      t.jsonb :anonymized_debrief
    end
  end
end
