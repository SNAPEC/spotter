class CreateAccessLogs < ActiveRecord::Migration[8.1]
  def change
    # report_id is deliberately not a foreign key: the trail survives the report's deletion.
    create_table :access_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.uuid :report_id, null: false, index: true
      t.string :action, null: false
      t.datetime :created_at, null: false

      t.check_constraint "action IN (#{AccessLog::ACTIONS.map { |value| connection.quote(value) }.join(", ")})", name: "access_logs_action_check"
    end
  end
end
