class Narrative < ApplicationRecord
  # The five debriefing questions of taxonomy v0: what led to the event, what worked, what to do
  # differently, what already changed in practice, message to other instructors.
  DEBRIEF_FIELDS = %w[debrief_causes debrief_what_worked debrief_do_differently debrief_changes_made debrief_message].freeze

  belongs_to :report

  encrypts :raw_text, *DEBRIEF_FIELDS

  validate :no_raw_text_once_decided

  def purge_raw!
    update!(raw_text: nil, **DEBRIEF_FIELDS.index_with(nil))
  end

  private
    # Checked against the stored status: a stale copy of the report must not let raw text back in.
    def no_raw_text_once_decided
      return if [ "raw_text", *DEBRIEF_FIELDS ].all? { |field| self[field].nil? }

      errors.add(:raw_text, :invalid) if Report.decided.exists?(report_id)
    end
end
