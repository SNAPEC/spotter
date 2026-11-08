class CreateTaxonomyOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :taxonomy_options do |t|
      t.references :taxonomy_field, null: false, foreign_key: true
      t.string :code, null: false
      t.string :label, null: false
      t.text :definition
      t.integer :position, null: false
      t.index [ :taxonomy_field_id, :code ], unique: true
    end
  end
end
