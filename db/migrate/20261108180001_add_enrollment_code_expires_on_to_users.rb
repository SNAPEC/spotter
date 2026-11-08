class AddEnrollmentCodeExpiresOnToUsers < ActiveRecord::Migration[8.1]
  def change
    # A day, not a timestamp: enough to expire the code without recording when it was issued to the minute.
    add_column :users, :enrollment_code_expires_on, :date
  end
end
