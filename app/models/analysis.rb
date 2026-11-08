# The extractor's coded proposals for a report, then the analyst's changes and decisions on them.
class Analysis < ApplicationRecord
  STATUSES = %w[proposed reviewed].freeze
  PROVIDERS = %w[fake scaleway].freeze

  belongs_to :report

  validates :status, inclusion: { in: STATUSES }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :model, :prompt_version, presence: true

  # Excerpts quote the declarant's narrative, and modifications may too: neither outlives the decision.
  def strip_raw_excerpts!
    update!(proposals: without_excerpts(proposals), modifications: {})
  end

  private
    def without_excerpts(value)
      case value
      when Hash then value.except("excerpt").transform_values { |item| without_excerpts(item) }
      when Array then value.map { |item| without_excerpts(item) }
      else value
      end
    end
end
