# One message of the exchange between an analyst and the declarant about a report under analysis.
class Clarification < ApplicationRecord
  include ReadOnlyOnceDecided

  AUTHORS = %w[analyst declarant].freeze

  belongs_to :report

  encrypts :body

  validates :author, inclusion: { in: AUTHORS }
  validates :body, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
end
