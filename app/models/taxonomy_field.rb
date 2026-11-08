class TaxonomyField < ApplicationRecord
  KINDS = %w[single multi text integer].freeze
  SCOPES = %w[report casualty].freeze

  belongs_to :taxonomy_version
  attr_readonly :taxonomy_version_id
  has_many :options, -> { order(:position) }, class_name: "TaxonomyOption", dependent: :destroy

  validates :code, :group, :label, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :scope, inclusion: { in: SCOPES }

  before_update :refuse_if_published
  before_destroy :refuse_if_published
  before_create :refuse_if_published

  private

  def refuse_if_published
    return unless taxonomy_version.published?

    errors.add(:base, :published_version)
    throw :abort
  end
end
