# submit! needs an event type and a narrative; most specs only care about what happens after.
module Submittable
  def submittable(report)
    return report unless report.open_draft?

    content = {}
    content[:event_type] = "near_miss" if report.event_type.blank?
    content[:narrative_attributes] = { raw_text: "Fictional story." } if report.narrative&.raw_text.blank?
    report.save_draft!(content) if content.any?
    report
  end
end

RSpec.configure { |config| config.include Submittable }
