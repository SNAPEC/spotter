# Excerpts quote the narrative: they are stored as encrypted JSON text until the decision. Rows written
# before this migration hold clear JSON and are not readable afterwards (pre-release: reseed).
class EncryptAnalysisExcerpts < ActiveRecord::Migration[8.1]
  def up
    %i[proposals modifications].each do |column|
      change_column_default :analyses, column, from: {}, to: nil
      change_column :analyses, column, :text, using: "#{column}::text"
    end
  end

  def down
    %i[proposals modifications].each do |column|
      change_column :analyses, column, :jsonb, using: "#{column}::jsonb", default: {}
    end
  end
end
