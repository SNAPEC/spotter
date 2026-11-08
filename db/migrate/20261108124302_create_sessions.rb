class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    # No IP, user agent or timestamps: a session must not reveal where or when someone signed in.
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.boolean :passkey_verified, null: false, default: false
    end
  end
end
