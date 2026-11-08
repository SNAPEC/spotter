require "rails_helper"

RSpec.describe TaxonomyVersion do
  let(:path) { Rails.root.join("db/seeds/taxonomy_v0.yml") }
  let(:version) { described_class.import!(path) }

  describe ".import!" do
    it "creates the fields and options of the v0 file" do
      expect(version.number).to eq(0)
      expect(version.fields.count).to eq(40)
      expect(version.options_for("cause").size).to be >= 18
      expect(version.options_for("severity").size).to eq(6)
      expect(version.fields.pluck(:position)).to eq((0...40).to_a)
    end

    it "keeps the full label of club_or_other" do
      option = version.fields.flat_map(&:options).find { |o| o.code == "club_or_other" }
      expect(option.label).to eq("Club, collectivité ou autre")
    end

    it "raises on unexpected keys and on missing label or code" do
      bad = lambda do |yaml|
        file = Tempfile.new([ "taxonomy", ".yml" ])
        file.write(yaml)
        file.close
        file.path
      end
      stray = "number: 9\nfields:\n  - code: a\n    group: g\n    kind: single\n    scope: report\n    label: A\n    options:\n      - { code: x, label: X, \"oops\": }\n"
      no_label = "number: 9\nfields:\n  - code: a\n    group: g\n    kind: text\n    scope: report\n"
      expect { described_class.import!(bad.call(stray)) }.to raise_error(TaxonomyVersion::InvalidImport, /oops/)
      expect { described_class.import!(bad.call(no_label)) }.to raise_error(TaxonomyVersion::InvalidImport, /label/)
      expect(described_class.exists?(number: 9)).to be(false)
    end

    it "raises a translated RecordInvalid on a blank field code" do
      version
      expect { version.fields.create!(code: "", group: "g", kind: "text", scope: "report", position: 99, label: "X") }
        .to raise_error(ActiveRecord::RecordInvalid, /doit être renseigné/)
    end

    it "refuses to import the same number twice" do
      version
      expect { described_class.import!(path) }.to raise_error(TaxonomyVersion::AlreadyImported)
    end
  end

  describe ".current" do
    it "is the latest published version" do
      version.publish!
      draft = described_class.create!(number: 1)
      draft.fields.create!(code: "d", group: "g", kind: "text", scope: "report", position: 0, label: "D")
      expect(described_class.current).to eq(version)
      draft.publish!
      expect(described_class.current).to eq(draft)
    end

    it "is nil when nothing is published" do
      version
      expect(described_class.current).to be_nil
    end
  end

  describe "immutability once published" do
    before { version.publish! }

    it "refuses to update a field or an option" do
      field = version.fields.find_by!(code: "cause")
      option = field.options.first
      expect(field.update(label: "Autre")).to be(false)
      expect(option.update(label: "Autre")).to be(false)
      expect(field.reload.label).not_to eq("Autre")
      expect(option.reload.label).not_to eq("Autre")
    end

    it "refuses to destroy a field, an option or the version" do
      field = version.fields.find_by!(code: "cause")
      expect(field.options.first.destroy).to be(false)
      expect(field.destroy).to be(false)
      expect(version.destroy).to be(false)
      expect(described_class.exists?(version.id)).to be(true)
      expect(field.options.count).to be >= 18
    end

    it "refuses to unpublish or renumber the version" do
      expect(version.update(published_at: nil)).to be(false)
      expect(version.errors.full_messages).to eq([ "Une version publiée de la taxonomie est immuable." ])
      expect(version.update(number: 5)).to be(false)
      expect(version.reload.published_at).to be_present
      expect(version.number).to eq(0)
    end

    it "refuses to move a field or an option out of its published parent" do
      draft = described_class.create!(number: 1)
      draft_field = draft.fields.create!(code: "d", group: "g", kind: "single", scope: "report", position: 0, label: "D")
      field = version.fields.find_by!(code: "cause")
      option = field.options.first
      expect { field.update(taxonomy_version: draft) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect { option.update(taxonomy_field: draft_field) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect(field.reload.taxonomy_version).to eq(version)
      expect(option.reload.taxonomy_field).to eq(field)
    end

    it "refuses to add a field" do
      expect(version.fields.build(code: "x", group: "g", kind: "text", scope: "report", position: 99, label: "X").save).to be(false)
    end
  end

  it "allows editing a draft" do
    field = version.fields.find_by!(code: "cause")
    expect(field.update(label: "Autre")).to be(true)
    expect(field.destroy).to be_truthy
  end

  describe "database constraints" do
    it "rejects an unknown kind or scope and a duplicate code" do
      field = version.fields.first
      expect { field.update_column(:kind, "bogus") }.to raise_error(ActiveRecord::StatementInvalid)
      expect { field.update_column(:scope, "bogus") }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects a duplicate field code in one version" do
      expect do
        version.fields.create!(code: "cause", group: "g", kind: "text", scope: "report", position: 99, label: "X")
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#validate_answers" do
    let(:valid_cause) { version.options_for("cause").first.code }
    let(:report_fields) { version.fields.where(scope: "report") }

    it "accepts valid answers" do
      multi = report_fields.find_by!(kind: "multi")
      integer = report_fields.find_by!(kind: "integer")
      answers = { "cause" => valid_cause, multi.code => [ multi.options.first.code ], integer.code => 3 }
      expect(version.validate_answers(answers, scope: :report)).to eq([])
    end

    it "flags an unknown option" do
      expect(version.validate_answers({ "cause" => "inconnue" }, scope: :report)).to eq([ "cause.invalid_option" ])
    end

    it "refuses an array for a single field" do
      expect(version.validate_answers({ "cause" => [ valid_cause ] }, scope: :report)).to eq([ "cause.invalid_option" ])
    end

    it "flags an unknown field code" do
      expect(version.validate_answers({ "nope" => "x" }, scope: :report)).to eq([ "nope.unknown_field" ])
    end

    it "flags a multi field that is not a list and invalid items" do
      multi = report_fields.find_by!(kind: "multi")
      expect(version.validate_answers({ multi.code => "x" }, scope: :report)).to eq([ "#{multi.code}.not_a_list" ])
      expect(version.validate_answers({ multi.code => [ "zzz" ] }, scope: :report)).to eq([ "#{multi.code}.invalid_option" ])
    end

    it "flags a non-integer and any free-text answer" do
      integer = report_fields.find_by!(kind: "integer")
      text = report_fields.find_by!(kind: "text")
      expect(version.validate_answers({ integer.code => "3" }, scope: :report)).to eq([ "#{integer.code}.not_an_integer" ])
      expect(version.validate_answers({ text.code => 3 }, scope: :report)).to eq([ "#{text.code}.free_text" ])
    end

    it "accepts nil for a known field only when told the answer may be unstated" do
      integer = report_fields.find_by!(kind: "integer")
      answers = { "cause" => nil, integer.code => nil }

      expect(version.validate_answers(answers, scope: :report)).to eq([ "cause.invalid_option", "#{integer.code}.not_an_integer" ])
      expect(version.validate_answers(answers, scope: :report, allow_unstated: true)).to eq([])
      expect(version.validate_answers({ "nope" => nil }, scope: :report, allow_unstated: true)).to eq([ "nope.unknown_field" ])
    end

    it "only accepts fields of the given scope" do
      casualty_field = version.fields.find_by!(scope: "casualty")
      expect(version.validate_answers({ casualty_field.code => "x" }, scope: :report)).to eq([ "#{casualty_field.code}.unknown_field" ])
      expect(version.validate_answers({ "cause" => valid_cause }, scope: :casualty)).to eq([ "cause.unknown_field" ])
    end
  end

  describe "#validate_answers with malformed input" do
    it "refuses anything but a hash" do
      expect(version.validate_answers(nil, scope: :report)).to eq([ "answers.not_a_hash" ])
      expect(version.validate_answers("x", scope: :report)).to eq([ "answers.not_a_hash" ])
    end

    it "flags duplicate values of a multi field and negative integers" do
      multi = version.fields.find_by!(scope: "report", kind: "multi")
      code = multi.options.first.code
      integer = version.fields.find_by!(scope: "report", kind: "integer")
      expect(version.validate_answers({ multi.code => [ code, code ] }, scope: :report)).to eq([ "#{multi.code}.duplicate_option" ])
      expect(version.validate_answers({ integer.code => -1 }, scope: :report)).to eq([ "#{integer.code}.out_of_range" ])
      expect(version.validate_answers({ integer.code => 0 }, scope: :report)).to eq([])
    end
  end

  describe "#publish!" do
    it "refuses a version without fields" do
      empty = described_class.create!(number: 7)
      expect { empty.publish! }.to raise_error(ActiveRecord::RecordInvalid, /sans champ/)
      expect(empty.reload.published_at).to be_nil
    end
  end

  describe "#options_for" do
    it "returns options in order, and nothing for an unknown field" do
      expect(version.options_for("severity").map(&:position)).to eq((0...6).to_a)
      expect(version.options_for("nope")).to eq([])
    end
  end
end
