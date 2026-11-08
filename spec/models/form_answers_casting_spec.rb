require "rails_helper"

RSpec.describe "Casting of form answers", type: :model do
  before { TaxonomyVersion.import!(Rails.root.join("db/seeds/taxonomy_v0.yml")).publish! }

  let(:user) { User.create!(email: "lea.martin@example.com") }
  let(:report) { Report.start_draft!(mode: "confidential", user: user).first }
  let(:multi_field) { TaxonomyField.where(kind: "multi", scope: "report").order(:position).first }
  let(:multi_code) { multi_field.code }
  let(:option) { multi_field.options.first.code }

  it "turns digit strings into integers for integer fields" do
    report.save_draft!(answers: { "clients_count" => "3", "instructors_count" => " 12 " })

    expect(report.reload.answers).to eq("clients_count" => 3, "instructors_count" => 12)
  end

  it "keeps a non-numeric string for the validation to refuse" do
    expect { report.save_draft!(answers: { "clients_count" => "trois" }) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { report.save_draft!(answers: { "clients_count" => "-1" }) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "does not turn numbers into anything else" do
    expect { report.save_draft!(answers: { "environment" => 3 }) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { report.save_draft!(answers: { "environment" => "indoors" }) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "accepts values already of the right type" do
    report.save_draft!(answers: { "clients_count" => 4, "environment" => "indoor" })

    expect(report.reload.answers).to eq("clients_count" => 4, "environment" => "indoor")
  end

  it "removes the keys posted blank, nil or with an empty list" do
    report.save_draft!(answers: { "environment" => "", "clients_count" => nil, "instructors_count" => "", multi_code => [ "", nil ] })

    expect(report.reload.answers).to eq({})
  end

  it "drops blank items from a list" do
    report.save_draft!(answers: { multi_code => [ "", option, nil ] })

    expect(report.reload.answers).to eq(multi_code => [ option ])
  end

  it "keeps refusing an unknown field, a blank one excepted" do
    expect { report.save_draft!(answers: { "nope" => "x" }) }.to raise_error(ActiveRecord::RecordInvalid)

    report.save_draft!(answers: { "nope" => "" })
    expect(report.reload.answers).to eq({})
  end

  it "casts a casualty's answers in the casualty scope" do
    report.save_draft!(casualties_attributes: [ { severity: "", answers: { "age_range" => "", "experience" => "beginner" } } ])

    casualty = report.reload.casualties.sole
    expect(casualty.severity).to be_nil
    expect(casualty.answers).to eq("experience" => "beginner")
  end

  it "removes blank free-text answers" do
    report.save_draft!(narrative_attributes: { free_text_answers: { "material_damage" => "" } })

    expect(report.reload.narrative.free_text_answers).to eq({})
  end
end
