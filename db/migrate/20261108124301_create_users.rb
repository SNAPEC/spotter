class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    # No timestamps: an updated_at would reveal the last sign-in.
    create_table :users do |t|
      t.string :email, null: false
      t.string :role, null: false, default: "declarant"
      t.date :membership_expires_on
      t.integer :login_token_version, null: false, default: 0

      t.check_constraint "role IN (#{User::ROLES.map { |role| connection.quote(role) }.join(", ")})", name: "users_role_check"
    end
    add_index :users, :email, unique: true
  end
end
