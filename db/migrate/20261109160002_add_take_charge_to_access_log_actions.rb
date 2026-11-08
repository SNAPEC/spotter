class AddTakeChargeToAccessLogActions < ActiveRecord::Migration[8.1]
  def up
    replace_action_check(AccessLog::ACTIONS)
  end

  def down
    replace_action_check(AccessLog::ACTIONS - %w[take_charge])
  end

  private
    def replace_action_check(actions)
      remove_check_constraint :access_logs, name: "access_logs_action_check"
      add_check_constraint :access_logs, "action IN (#{actions.map { |value| connection.quote(value) }.join(", ")})", name: "access_logs_action_check"
    end
end
