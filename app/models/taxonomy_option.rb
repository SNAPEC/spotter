class TaxonomyOption < ApplicationRecord
  belongs_to :taxonomy_field

  validates :code, :label, presence: true

  before_create :refuse_if_published
  before_update :refuse_if_published
  before_destroy :refuse_if_published

  private

  def refuse_if_published
    return unless taxonomy_field.taxonomy_version.published?

    errors.add(:base, "published taxonomy versions are immutable")
    throw :abort
  end
end
