class AddActionCheckToAuditEvents < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :audit_events, "action IN (#{AuditEvent::ACTIONS.map { |value| connection.quote(value) }.join(", ")})", name: "audit_events_action_check"
  end
end
