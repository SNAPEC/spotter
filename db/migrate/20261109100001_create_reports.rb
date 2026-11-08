class CreateReports < ActiveRecord::Migration[8.1]
  def change
    # No timestamps: a creation or update time would help tie a report to its author.
    create_table :reports, id: :uuid do |t|
      t.string :event_type
      t.string :mode, null: false
      t.string :status, null: false, default: "draft"
      t.string :discipline
      t.string :environment
      t.string :cause
      t.string :severity
      t.jsonb :answers, null: false, default: {}
      t.references :taxonomy_version, null: false, foreign_key: true
      t.date :submitted_on
      t.date :draft_expires_on
      t.string :draft_token_digest
      t.string :tracking_code_digest

      t.index :status
      t.index :draft_expires_on
      t.index :draft_token_digest, unique: true
      t.index :tracking_code_digest, unique: true
      t.check_constraint "event_type IN (#{Report::EVENT_TYPES.map { |value| connection.quote(value) }.join(", ")})", name: "reports_event_type_check"
      t.check_constraint "mode IN (#{Report::MODES.map { |value| connection.quote(value) }.join(", ")})", name: "reports_mode_check"
      t.check_constraint "status IN (#{Report::STATUSES.map { |value| connection.quote(value) }.join(", ")})", name: "reports_status_check"
    end
  end
end
