class CreateTaxonomyVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :taxonomy_versions do |t|
      t.integer :number, null: false
      t.datetime :published_at
      t.index :number, unique: true
    end
  end
end
