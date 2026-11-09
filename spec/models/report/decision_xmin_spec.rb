require "rails_helper"
require Rails.root.join("spec/support/decidable")
require Rails.root.join("spec/support/submittable")

# Outside a test transaction: inside one, every row would share the test's transaction id.
RSpec.describe Report, "rows kept after the decision", type: :model do
  self.use_transactional_tests = false

  after do
    connection = ActiveRecord::Base.connection
    connection.truncate_tables(*(connection.tables - %w[schema_migrations ar_internal_metadata]))
  end

  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:analyst) { User.create!(email: "chloe.bernard@example.com", role: "analyst") }

  def xmins(table, report)
    column = table == "reports" ? "id" : "report_id"
    ActiveRecord::Base.connection.select_values(
      "SELECT xmin::text FROM #{table} WHERE #{column} = #{ActiveRecord::Base.connection.quote(report.id)}"
    )
  end

  %i[validate! reject!].each do |decision|
    it "carry the transaction id of the decision after #{decision}, not that of the declarant's last entry" do
      report, = Report.start_draft!(mode: "anonymous")
      report.save_draft!(
        narrative_attributes: { raw_text: "Récit fictif." },
        casualties_attributes: [ { severity: "minor" }, { severity: "severe" } ]
      )
      submittable(report).submit!
      Report::Analyzer.new.call(report, revision: report.content_revision)
      expect(xmins("casualties", report).uniq).not_to eq(xmins("reports", report))

      decide_with_text!(report, decision, analyst)

      decision_xmin = xmins("reports", report)
      expect(decision_xmin.size).to eq(1)
      %w[casualties narratives analyses].each do |table|
        expect(xmins(table, report)).to all(eq(decision_xmin.first)), table
      end
    end
  end
end
