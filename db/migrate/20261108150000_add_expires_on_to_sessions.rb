class AddExpiresOnToSessions < ActiveRecord::Migration[8.1]
  def change
    # A month-rounded expiry date, the only date a session keeps.
    add_column :sessions, :expires_on, :date, null: false
    add_index :sessions, :expires_on
  end
end
