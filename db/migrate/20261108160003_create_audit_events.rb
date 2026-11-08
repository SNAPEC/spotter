class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    # Only who did what to whom, and when: no IP address, no user agent.
    create_table :audit_events do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.references :subject, polymorphic: true, null: false
      t.datetime :created_at, null: false
    end
  end
end
