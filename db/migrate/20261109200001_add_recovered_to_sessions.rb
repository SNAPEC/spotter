# A session opened with a recovery code reaches only passkey enrolment and sign out.
class AddRecoveredToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :recovered, :boolean, default: false, null: false
  end
end
