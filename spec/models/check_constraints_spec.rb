require "rails_helper"

# Every "column IN (...)" check constraint lists exactly the values of its model's constant, named after
# the column (status -> STATUSES): a value added to one and not the other fails here.
RSpec.describe "Check constraints", type: :model do
  let(:connection) { ActiveRecord::Base.connection }
  let(:models) do
    Rails.application.eager_load!
    ApplicationRecord.descendants.reject(&:abstract_class?).index_by(&:table_name)
  end

  def list_constraints
    connection.tables.flat_map do |table|
      connection.check_constraints(table).filter_map do |constraint|
        match = constraint.expression.match(/\A\(?(\w+)::text = ANY \(\(?ARRAY\[(.*)\]\)?(::text\[\])?\)\)?\z/)
        [ table, match[1], match[2].scan(/'([^']*)'/).flatten ] if match
      end
    end
  end

  it "match their Ruby constant" do
    constraints = list_constraints

    expect(constraints.map { |table, column, _| "#{table}.#{column}" }).to include(
      "reports.status", "analyses.provider", "access_logs.action", "audit_events.action", "users.role"
    )
    constraints.each do |table, column, values|
      model = models.fetch(table)
      constant = column.pluralize.upcase

      expect(model.const_defined?(constant, false)).to be(true), "#{model}::#{constant} is missing for #{table}.#{column}"
      expect(values).to match_array(model.const_get(constant)), "#{table}.#{column} differs from #{model}::#{constant}"
    end
  end

  it "refuses an audit event action the model does not know" do
    user = User.create!(email: "chloe.bernard@example.com", role: "admin")

    expect { connection.execute(<<~SQL) }.to raise_error(ActiveRecord::StatementInvalid, /audit_events_action_check/)
      INSERT INTO audit_events (actor_id, action, subject_type, subject_id, created_at)
      VALUES (#{user.id}, 'unknown.action', 'User', #{user.id}, now())
    SQL
  end
end
