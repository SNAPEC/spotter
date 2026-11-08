class DropDecisionsFromAnalyses < ActiveRecord::Migration[8.1]
  def change
    remove_column :analyses, :decisions, :jsonb, null: false, default: {}
  end
end
