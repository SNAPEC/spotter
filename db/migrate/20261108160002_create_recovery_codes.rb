class CreateRecoveryCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :recovery_codes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :digest, null: false
    end
    add_index :recovery_codes, :digest, unique: true
  end
end
