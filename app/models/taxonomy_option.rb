class TaxonomyOption < ApplicationRecord
  belongs_to :taxonomy_field
  attr_readonly :taxonomy_field_id

  validates :code, :label, presence: true

  before_create :refuse_if_published
  before_update :refuse_if_published
  before_destroy :refuse_if_published

  private

  def refuse_if_published
    return unless taxonomy_field.taxonomy_version.published?

    errors.add(:base, :published_version)
    throw :abort
  end
end
