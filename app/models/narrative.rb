class Narrative < ApplicationRecord
  include ReadOnlyOnceDecided

  # The five debriefing questions of taxonomy v0: what led to the event, what worked, what to do
  # differently, what already changed in practice, message to other instructors.
  DEBRIEF_FIELDS = %w[debrief_causes debrief_what_worked debrief_do_differently debrief_changes_made debrief_message].freeze

  belongs_to :report

  encrypts :raw_text, *DEBRIEF_FIELDS

  def purge_raw!
    update!(raw_text: nil, **DEBRIEF_FIELDS.index_with(nil))
  end

  private
    def kept_after_decision?
      [ "raw_text", *DEBRIEF_FIELDS ].all? { |field| self[field].nil? }
    end
end
