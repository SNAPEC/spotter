# Purge dates move from month ends to quarter ends, and are recomputed from each account's last
# session: 12 months after it expires, else 30 days from now, rounded up to the end of the quarter.
class RoundPurgeOnToQuarters < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :users, name: "users_purge_on_end_of_month_check"
    execute <<~SQL
      UPDATE users SET purge_on = (date_trunc('quarter', COALESCE(
        (SELECT MAX(sessions.expires_on) + interval '12 months' FROM sessions WHERE sessions.user_id = users.id),
        CURRENT_DATE + 30
      )) + interval '3 months' - interval '1 day')::date
    SQL
    add_check_constraint :users, "EXTRACT(day FROM purge_on + 1) = 1 AND EXTRACT(month FROM purge_on + 1) IN (1, 4, 7, 10)",
      name: "users_purge_on_end_of_quarter_check"
  end

  def down
    remove_check_constraint :users, name: "users_purge_on_end_of_quarter_check"
    add_check_constraint :users, "EXTRACT(day FROM purge_on + 1) = 1", name: "users_purge_on_end_of_month_check"
  end
end
