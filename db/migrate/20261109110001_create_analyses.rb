class CreateAnalyses < ActiveRecord::Migration[8.1]
  def change
    # No timestamps, like every table tied to a report.
    create_table :analyses, id: :uuid do |t|
      t.references :report, type: :uuid, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :model, null: false
      t.string :prompt_version, null: false
      t.string :status, null: false, default: "proposed"
      t.jsonb :proposals, null: false, default: {}
      t.jsonb :modifications, null: false, default: {}
      t.jsonb :decisions, null: false, default: {}

      t.index [ :report_id, :prompt_version ], unique: true
      t.check_constraint "status IN (#{Analysis::STATUSES.map { |value| connection.quote(value) }.join(", ")})", name: "analyses_status_check"
      t.check_constraint "provider IN (#{Analysis::PROVIDERS.map { |value| connection.quote(value) }.join(", ")})", name: "analyses_provider_check"
    end
  end
end
