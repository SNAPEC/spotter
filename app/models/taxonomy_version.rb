class TaxonomyVersion < ApplicationRecord
  class AlreadyImported < StandardError; end
  class InvalidImport < StandardError; end

  has_many :fields, -> { order(:position) }, class_name: "TaxonomyField", dependent: :destroy

  validates :number, presence: true, uniqueness: true

  before_destroy { throw :abort if published? }

  scope :published, -> { where.not(published_at: nil) }

  def self.current
    published.order(number: :desc).first
  end

  FIELD_KEYS = %w[code group kind scope label options].freeze
  OPTION_KEYS = %w[code label definition].freeze

  def self.import!(path)
    data = YAML.safe_load_file(path)
    check_import_keys!(data)
    raise AlreadyImported, "taxonomy version #{data.fetch("number")} already exists" if exists?(number: data.fetch("number"))

    transaction do
      version = create!(number: data.fetch("number"))
      data.fetch("fields").each.with_index do |attrs, index|
        field = version.fields.create!(attrs.slice("code", "group", "kind", "scope", "label").merge("position" => index))
        Array(attrs["options"]).each.with_index do |option, position|
          field.options.create!(option.slice("code", "label", "definition").merge("position" => position))
        end
      end
      version
    end
  end

  def self.check_import_keys!(data)
    data.fetch("fields").each do |field|
      check_keys!(field, FIELD_KEYS, %w[code label], "field #{field["code"].inspect}")
      Array(field["options"]).each do |option|
        check_keys!(option, OPTION_KEYS, %w[code label], "option #{option["code"].inspect} of #{field["code"]}")
      end
    end
  end
  private_class_method :check_import_keys!

  def self.check_keys!(hash, allowed, required, where)
    unexpected = hash.keys - allowed
    missing = required.select { |key| hash[key].blank? }
    return if unexpected.empty? && missing.empty?

    raise InvalidImport, "#{where}: unexpected keys #{unexpected.inspect}, missing #{missing.inspect}"
  end
  private_class_method :check_keys!

  def published?
    published_at.present?
  end

  def publish!
    update!(published_at: Time.current) unless published?
    self
  end

  def options_for(field_code)
    field_by_code(field_code)&.options.to_a
  end

  # Codes are "<field>.<error>": unknown_field, invalid_option, not_a_list, not_a_string, not_an_integer.
  def validate_answers(answers, scope:)
    fields_by_code = fields.where(scope: scope.to_s).includes(:options).index_by(&:code)
    answers.flat_map do |code, value|
      field = fields_by_code[code.to_s]
      field ? answer_errors(field, value) : [ "#{code}.unknown_field" ]
    end
  end

  private

  def field_by_code(code)
    fields.includes(:options).find_by(code: code.to_s)
  end

  def answer_errors(field, value)
    codes = field.options.map(&:code)
    error = case field.kind
    when "single" then "invalid_option" unless value.is_a?(String) && codes.include?(value)
    when "multi"
      if !value.is_a?(Array) then "not_a_list"
      elsif !value.all? { |item| item.is_a?(String) && codes.include?(item) } then "invalid_option"
      end
    when "text" then "not_a_string" unless value.is_a?(String)
    when "integer" then "not_an_integer" unless value.is_a?(Integer)
    end
    error ? [ "#{field.code}.#{error}" ] : []
  end
end
