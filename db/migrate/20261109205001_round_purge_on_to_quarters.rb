# Purge dates move from month ends to quarter ends. The new date is the later of the existing one
# rounded up to its quarter end, and one recomputed from the account's last session (12 months after
# it expires, else 30 days from now) rounded up too. Sessions are deleted at sign-out and expiry, so
# the recomputation alone could pull a date earlier; this never does.
class RoundPurgeOnToQuarters < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :users, name: "users_purge_on_end_of_month_check"
    execute <<~SQL
      UPDATE users SET purge_on = (date_trunc('quarter', GREATEST(
        users.purge_on,
        COALESCE(
          (SELECT MAX(sessions.expires_on) + interval '12 months' FROM sessions WHERE sessions.user_id = users.id),
          CURRENT_DATE + 30
        )
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
