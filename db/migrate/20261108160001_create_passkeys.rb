class CreatePasskeys < ActiveRecord::Migration[8.1]
  def change
    # No timestamps: they would reveal when a staff member enrolled or last signed in.
    create_table :passkeys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :nickname
    end
    add_index :passkeys, :external_id, unique: true
  end
end
