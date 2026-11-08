class Narrative < ApplicationRecord
  DEBRIEF_FIELDS = %w[debrief_context debrief_causes debrief_response debrief_consequences debrief_lessons].freeze

  belongs_to :report

  encrypts :raw_text, *DEBRIEF_FIELDS

  def purge_raw!
    update!(raw_text: nil, **DEBRIEF_FIELDS.index_with(nil))
  end
end
