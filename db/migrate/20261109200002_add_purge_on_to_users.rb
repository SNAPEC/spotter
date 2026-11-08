# Unused declarant accounts are purged. A single date, rounded to the end of a month, stands in for
# timestamps the table must not hold.
class AddPurgeOnToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :purge_on, :date
    up_only do
      execute <<~SQL
        UPDATE users SET purge_on = (date_trunc('month', CURRENT_DATE + 30) + interval '1 month' - interval '1 day')::date
      SQL
    end
    change_column_null :users, :purge_on, false
    add_index :users, :purge_on
    add_check_constraint :users, "EXTRACT(day FROM purge_on + 1) = 1", name: "users_purge_on_end_of_month_check"
  end
end
