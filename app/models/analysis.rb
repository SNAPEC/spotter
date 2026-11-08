# The extractor's coded proposals for a report, then the analyst's changes and decisions on them.
class Analysis < ApplicationRecord
  STATUSES = %w[proposed reviewed failed].freeze
  PROVIDERS = %w[fake scaleway].freeze

  belongs_to :report

  validates :status, inclusion: { in: STATUSES }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :model, :prompt_version, presence: true

  # Excerpts quote the declarant's narrative, and modifications may too: neither outlives the decision.
  # Only each proposal's coded value is kept, whatever else was stored.
  def strip_raw_excerpts!
    update!(proposals: proposals.transform_values { |proposal| proposal.is_a?(Hash) ? proposal.slice("value") : {} }, modifications: {})
  end
end
