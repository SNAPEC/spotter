class CreateCasualties < ActiveRecord::Migration[8.1]
  def change
    create_table :casualties do |t|
      t.references :report, type: :uuid, null: false, foreign_key: true
      t.string :severity
      t.jsonb :answers, null: false, default: {}
    end
  end
end
