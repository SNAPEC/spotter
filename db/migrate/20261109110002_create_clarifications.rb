class CreateClarifications < ActiveRecord::Migration[8.1]
  def change
    # No timestamps: the position orders the exchange without dating it.
    create_table :clarifications, id: :uuid do |t|
      t.references :report, type: :uuid, null: false, foreign_key: true, index: false
      t.string :author, null: false
      t.text :body, null: false
      t.integer :position, null: false

      t.index [ :report_id, :position ], unique: true
      t.check_constraint "author IN (#{Clarification::AUTHORS.map { |value| connection.quote(value) }.join(", ")})", name: "clarifications_author_check"
    end
  end
end
