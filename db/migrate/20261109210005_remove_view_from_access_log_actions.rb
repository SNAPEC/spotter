# A GET never writes: viewing a report leaves no trail.
class RemoveViewFromAccessLogActions < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM access_logs WHERE action = 'view'"
    replace_action_check(AccessLog::ACTIONS)
  end

  # The deleted view rows are not restored.
  def down
    replace_action_check(%w[view take_charge ask_clarification validate reject])
  end

  private
    def replace_action_check(actions)
      remove_check_constraint :access_logs, name: "access_logs_action_check"
      add_check_constraint :access_logs, "action IN (#{actions.map { |value| connection.quote(value) }.join(", ")})", name: "access_logs_action_check"
    end
end
