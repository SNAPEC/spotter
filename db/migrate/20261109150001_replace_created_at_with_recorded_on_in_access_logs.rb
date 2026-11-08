# The exact time of an action could be matched against the mail provider's log: only the month is kept.
class ReplaceCreatedAtWithRecordedOnInAccessLogs < ActiveRecord::Migration[8.1]
  def up
    add_column :access_logs, :recorded_on, :date
    execute "UPDATE access_logs SET recorded_on = date_trunc('month', created_at)::date"
    change_column_null :access_logs, :recorded_on, false
    add_check_constraint :access_logs, "EXTRACT(DAY FROM recorded_on) = 1", name: "access_logs_recorded_on_month_check"
    remove_column :access_logs, :created_at
  end

  def down
    add_column :access_logs, :created_at, :datetime
    execute "UPDATE access_logs SET created_at = recorded_on"
    change_column_null :access_logs, :created_at, false
    remove_check_constraint :access_logs, name: "access_logs_recorded_on_month_check"
    remove_column :access_logs, :recorded_on
  end
end
