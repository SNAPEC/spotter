class CreateNarratives < ActiveRecord::Migration[8.1]
  def change
    create_table :narratives do |t|
      t.references :report, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.text :raw_text
      t.text :debrief_context
      t.text :debrief_causes
      t.text :debrief_response
      t.text :debrief_consequences
      t.text :debrief_lessons
      t.text :anonymized_text
      t.jsonb :anonymized_debrief
    end
  end
end
