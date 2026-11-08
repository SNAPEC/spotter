# The extractor's coded proposals for a report, then the analyst's changes and decisions on them.
class Analysis < ApplicationRecord
  include ReadOnlyOnceDecided

  STATUSES = %w[proposed reviewed failed].freeze
  PROVIDERS = %w[fake scaleway].freeze

  belongs_to :report

  %i[proposals modifications].each do |column|
    serialize column, coder: JSON
    attribute column, default: -> { {} }
    encrypts column
  end

  validates :status, inclusion: { in: STATUSES }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :model, :prompt_version, presence: true

  # Excerpts quote the declarant's narrative, and modifications may too: neither outlives the decision.
  # Only each proposal's coded value is kept, whatever else was stored.
  def strip_raw_excerpts!
    update!(proposals: proposals.transform_values { |proposal| proposal.is_a?(Hash) ? proposal.slice("value") : {} }, modifications: {})
  end

  private
    def kept_after_decision?
      modifications.blank? && proposals.to_h.values.all? { |proposal| proposal.is_a?(Hash) && (proposal.keys - [ "value" ]).empty? }
    end
end
