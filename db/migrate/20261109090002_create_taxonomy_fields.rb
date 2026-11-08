class CreateTaxonomyFields < ActiveRecord::Migration[8.1]
  def change
    create_table :taxonomy_fields do |t|
      t.references :taxonomy_version, null: false, foreign_key: true
      t.string :code, null: false
      t.string :group, null: false
      t.string :kind, null: false
      t.string :scope, null: false
      t.integer :position, null: false
      t.string :label, null: false
      t.index [ :taxonomy_version_id, :code ], unique: true
      t.check_constraint "kind IN (#{TaxonomyField::KINDS.map { |kind| connection.quote(kind) }.join(", ")})", name: "taxonomy_fields_kind_check"
      t.check_constraint "scope IN (#{TaxonomyField::SCOPES.map { |scope| connection.quote(scope) }.join(", ")})", name: "taxonomy_fields_scope_check"
    end
  end
end
